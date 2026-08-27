open Import
open Memo.O

module File = struct
  type t =
    | Workspace of Path.Source.t
    | Build of Path.Build.t

  let workspace path = Workspace path
  let build path = Build path

  let source_path = function
    | Workspace path -> Source_path.workspace path
    | Build path -> Source_path.build path
  ;;

  let path = function
    | Workspace path -> Path.source path
    | Build path -> Path.build path
  ;;

  let as_workspace = function
    | Workspace path -> Some path
    | Build _ -> None
  ;;

  let relative t loc path =
    match t with
    | Workspace file ->
      Path.Source.relative ~error_loc:loc (Path.Source.parent_exn file) path |> workspace
    | Build file ->
      Path.Build.relative ~error_loc:loc (Path.Build.parent_exn file) path |> build
  ;;

  let read = function
    | Workspace path ->
      let path = Path.Outside_build_dir.In_source_dir path in
      let* exists = Fs_memo.file_exists path in
      if exists then Fs_memo.file_contents path >>| Option.some else Memo.return None
    | Build path ->
      let path = Path.build path in
      let* exists = Build_system.file_exists path in
      if exists then Build_system.read_file path >>| Option.some else Memo.return None
  ;;

  let equal a b =
    match a, b with
    | Workspace a, Workspace b -> Path.Source.equal a b
    | Build a, Build b -> Path.Build.equal a b
    | Workspace _, Build _ | Build _, Workspace _ -> false
  ;;

  let diagnostic_name = function
    | Workspace path -> Path.Source.to_string path
    | Build path -> Path.Build.to_string path
  ;;

  let to_dyn t = Source_path.to_dyn (source_path t)
end

module Dir = struct
  type t =
    | Workspace of Path.Source.t
    | Build of Path.Build.t

  let workspace path = Workspace path
  let build path = Build path

  let source_path = function
    | Workspace path -> Source_path.workspace path
    | Build path -> Source_path.build path
  ;;

  let path = function
    | Workspace path -> Path.source path
    | Build path -> Path.build path
  ;;

  let basename = function
    | Workspace path -> Path.Source.basename path
    | Build path -> Path.Build.basename path
  ;;

  let file t filename =
    match t with
    | Workspace path -> Path.Source.relative_fname path filename |> File.workspace
    | Build path -> Path.Build.relative_fname path filename |> File.build
  ;;
end
