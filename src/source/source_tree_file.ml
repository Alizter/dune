open Import
open Memo.O

module File = struct
  type t =
    | Workspace of Path.Source.t
    | Loaded of Loaded_source.t * Path.Local.t

  let workspace path = Workspace path
  let loaded source path = Loaded (source, path)

  let source_path = function
    | Workspace path -> Source_path.workspace path
    | Loaded (source, path) -> Loaded_source.source_path source path |> Source_path.build
  ;;

  let as_workspace = function
    | Workspace path -> Some path
    | Loaded _ -> None
  ;;

  let relative t loc path =
    match t with
    | Workspace file ->
      Path.Source.relative ~error_loc:loc (Path.Source.parent_exn file) path |> workspace
    | Loaded (source, file) ->
      Path.Local.relative (Path.Local.parent_exn file) path |> loaded source
  ;;

  let read = function
    | Workspace path ->
      let path = Path.Outside_build_dir.In_source_dir path in
      let* exists = Fs_memo.file_exists path in
      if exists then Fs_memo.file_contents path >>| Option.some else Memo.return None
    | Loaded (source, path) ->
      let* exists = Loaded_source.file_exists source path in
      if exists
      then Loaded_source.read_file source path >>| Option.some
      else Memo.return None
  ;;

  let equal a b =
    match a, b with
    | Workspace a, Workspace b -> Path.Source.equal a b
    | Loaded (source, path), Loaded (source', path') ->
      Loaded_source.equal source source' && Path.Local.equal path path'
    | Workspace _, Loaded _ | Loaded _, Workspace _ -> false
  ;;

  let diagnostic_name = function
    | Workspace path -> Path.Source.to_string path
    | Loaded (source, path) -> Loaded_source.diagnostic_name source path
  ;;

  let to_dyn t = Source_path.to_dyn (source_path t)
end

module Dir = struct
  type t =
    | Workspace of Path.Source.t
    | Loaded of Loaded_source.t * Path.Local.t

  let workspace path = Workspace path
  let loaded source path = Loaded (source, path)

  let source_path = function
    | Workspace path -> Source_path.workspace path
    | Loaded (source, path) -> Loaded_source.source_path source path |> Source_path.build
  ;;

  let basename = function
    | Workspace path -> Path.Source.basename path
    | Loaded (_, path) -> Path.Local.basename path
  ;;

  let file t filename =
    match t with
    | Workspace path -> Path.Source.relative_fname path filename |> File.workspace
    | Loaded (source, path) ->
      Path.Local.relative_fname path filename |> File.loaded source
  ;;
end
