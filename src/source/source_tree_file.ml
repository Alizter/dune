open Import
open Memo.O

module Mount = struct
  type t =
    { logical_root : Path.Build.t
    ; backing_root : Path.Build.t
    }
end

module File = struct
  type t =
    | Workspace of Path.Source.t
    | Mounted of
        { mount : Mount.t
        ; logical : Path.Build.t
        ; backing : Path.Build.t
        }

  let workspace path = Workspace path
  let mounted ~mount ~logical ~backing = Mounted { mount; logical; backing }

  let source_path = function
    | Workspace path -> Path.Source.to_local path
    | Mounted { logical; _ } -> Dune_project.dir_in_context logical
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

  let parent_exn = function
    | Workspace file -> Workspace (Path.Source.parent_exn file)
    | Mounted { mount; logical; backing } ->
      Mounted
        { mount
        ; logical = Path.Build.parent_exn logical
        ; backing = Path.Build.parent_exn backing
        }
  ;;

  let relative t loc path =
    match t with
    | Workspace dir -> Workspace (Path.Source.relative ~error_loc:loc dir path)
    | Mounted { mount; logical; backing } ->
      let { Mount.logical_root; backing_root } = mount in
      let logical = Path.Build.relative ~error_loc:loc logical path in
      let backing = Path.Build.relative ~error_loc:loc backing path in
      if
        not
          (Path.Build.is_descendant logical ~of_:logical_root
           && Path.Build.is_descendant backing ~of_:backing_root)
      then
        User_error.raise
          ~loc
          [ Pp.textf "Included path %S is outside the mounted source tree." path ];
      Mounted { mount; logical; backing }
  ;;

  let exists = function
    | Workspace path -> Fs_memo.file_exists (Path.Outside_build_dir.In_source_dir path)
    | Mounted { backing; _ } -> Build_system.file_exists (Path.build backing)
  ;;

  let read t =
    let* exists = exists t in
    if not exists
    then Memo.return None
    else
      let+ contents =
        match t with
        | Workspace path ->
          Fs_memo.file_contents (Path.Outside_build_dir.In_source_dir path)
        | Mounted { backing; _ } -> Build_system.read_file (Path.build backing)
      in
      Some contents
  ;;

  let equal a b =
    match a, b with
    | Workspace a, Workspace b -> Path.Source.equal a b
    | Mounted a, Mounted b ->
      Path.Build.equal a.logical b.logical && Path.Build.equal a.backing b.backing
    | Workspace _, Mounted _ | Mounted _, Workspace _ -> false
  ;;

  let diagnostic_name t = Path.to_string (path t)

  let with_lexbuf_from_file t ~f =
    read t
    >>| function
    | Some contents -> f (Lexbuf.from_string contents ~fname:(diagnostic_name t))
    | None ->
      User_error.raise
        ~loc:(Loc.in_file (backing_path t))
        [ Pp.textf "File %s cannot be read." (diagnostic_name t) ]
  ;;
end

module Dir = struct
  include File

  let basename = function
    | Workspace path -> Path.Source.basename path
    | Mounted { logical; _ } -> Path.Build.basename logical
  ;;

  let file t filename =
    match t with
    | Workspace path -> Path.Source.relative_fname path filename |> File.workspace
    | Mounted { mount; logical; backing } ->
      File.mounted
        ~mount
        ~logical:(Path.Build.relative_fname logical filename)
        ~backing:(Path.Build.relative_fname backing filename)
  ;;
end
