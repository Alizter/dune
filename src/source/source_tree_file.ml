open Import
open Memo.O

module File = struct
  type mounted =
    { logical : Path.Build.t
    ; backing : Path.Build.t
    }

  type t =
    | Workspace of Path.Source.t
    | Mounted of mounted

  let workspace path = Workspace path
  let mounted ~logical ~backing = Mounted { logical; backing }

  let source_path = function
    | Workspace path -> Source_path.workspace path
    | Mounted { logical; _ } -> Source_path.build logical
  ;;

  let path = function
    | Workspace path -> Path.source path
    | Mounted { logical; _ } -> Path.build logical
  ;;

  let backing_path = function
    | Workspace path -> Path.source path
    | Mounted { backing; _ } -> Path.build backing
  ;;

  let as_workspace = function
    | Workspace path -> Some path
    | Mounted _ -> None
  ;;

  let relative t loc path =
    match t with
    | Workspace file ->
      Path.Source.relative ~error_loc:loc (Path.Source.parent_exn file) path |> workspace
    | Mounted { logical; backing } ->
      mounted
        ~logical:(Path.Build.relative ~error_loc:loc (Path.Build.parent_exn logical) path)
        ~backing:(Path.Build.relative ~error_loc:loc (Path.Build.parent_exn backing) path)
  ;;

  let read = function
    | Workspace path ->
      let path = Path.Outside_build_dir.In_source_dir path in
      let* exists = Fs_memo.file_exists path in
      if exists then Fs_memo.file_contents path >>| Option.some else Memo.return None
    | Mounted { backing = path; _ } ->
      let path = Path.build path in
      let* exists = Build_system.file_exists path in
      if exists then Build_system.read_file path >>| Option.some else Memo.return None
  ;;

  let equal a b =
    match a, b with
    | Workspace a, Workspace b -> Path.Source.equal a b
    | Mounted a, Mounted b ->
      Path.Build.equal a.logical b.logical && Path.Build.equal a.backing b.backing
    | Workspace _, Mounted _ | Mounted _, Workspace _ -> false
  ;;

  let diagnostic_name = function
    | Workspace path -> Path.Source.to_string path
    | Mounted { logical; _ } -> Path.Build.to_string logical
  ;;

  let to_dyn = function
    | Workspace path -> Dyn.variant "Workspace" [ Path.Source.to_dyn path ]
    | Mounted { logical; backing } ->
      Dyn.variant
        "Mounted"
        [ Dyn.record
            [ "logical", Path.Build.to_dyn logical; "backing", Path.Build.to_dyn backing ]
        ]
  ;;
end

module Dir = struct
  type mounted =
    { logical : Path.Build.t
    ; backing : Path.Build.t
    }

  type t =
    | Workspace of Path.Source.t
    | Mounted of mounted

  let workspace path = Workspace path
  let mounted ~logical ~backing = Mounted { logical; backing }

  let source_path = function
    | Workspace path -> Source_path.workspace path
    | Mounted { logical; _ } -> Source_path.build logical
  ;;

  let path = function
    | Workspace path -> Path.source path
    | Mounted { logical; _ } -> Path.build logical
  ;;

  let backing_path = function
    | Workspace path -> Path.source path
    | Mounted { backing; _ } -> Path.build backing
  ;;

  let basename = function
    | Workspace path -> Path.Source.basename path
    | Mounted { logical; _ } -> Path.Build.basename logical
  ;;

  let file t filename =
    match t with
    | Workspace path -> Path.Source.relative_fname path filename |> File.workspace
    | Mounted { logical; backing } ->
      File.mounted
        ~logical:(Path.Build.relative_fname logical filename)
        ~backing:(Path.Build.relative_fname backing filename)
  ;;
end
