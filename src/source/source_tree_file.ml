open Import
open Memo.O

module Backing = struct
  type t =
    | External of Path.External.t
    | Build of Path.Build.t

  let repr =
    Repr.variant
      "source-backing"
      [ Repr.case "External" Path.External.repr ~proj:(function
          | External path -> Some path
          | Build _ -> None)
      ; Repr.case "Build" Path.Build.repr ~proj:(function
          | Build path -> Some path
          | External _ -> None)
      ]
  ;;

  let equal a b =
    match a, b with
    | External a, External b -> Path.External.equal a b
    | Build a, Build b -> Path.Build.equal a b
    | External _, Build _ | Build _, External _ -> false
  ;;

  let hash = function
    | External path -> Poly.hash (0, Path.External.hash path)
    | Build path -> Poly.hash (1, Path.Build.hash path)
  ;;

  let to_dyn = Repr.to_dyn repr

  let path = function
    | External path -> Path.external_ path
    | Build path -> Path.build path
  ;;

  let append_local t local =
    match t with
    | External path -> External (Path.External.append_local path local)
    | Build path -> Build (Path.Build.append_local path local)
  ;;

  let relative_fname t name =
    match t with
    | External path -> External (Path.External.relative_fname path name)
    | Build path -> Build (Path.Build.relative_fname path name)
  ;;

  let parent_exn = function
    | External path -> External (Path.External.parent_exn path)
    | Build path -> Build (Path.Build.parent_exn path)
  ;;

  let fs_path path = Path.Outside_build_dir.External path

  let file_exists = function
    | External path -> Fs_memo.file_exists (fs_path path)
    | Build path -> Build_system.file_exists (Path.build path)
  ;;

  let read_file = function
    | External path -> Fs_memo.file_contents (fs_path path)
    | Build path -> Build_system.read_file (Path.build path)
  ;;

  let dir_contents = function
    | Build dir ->
      let+ contents = Build_system.directory_target_contents_opt ~dir in
      Ok contents
    | External dir ->
      let+ contents = Fs_memo.dir_contents (fs_path dir) in
      (match contents with
       | Error (Unix.ENOENT, _, _) -> Ok None
       | Error error -> Error error
       | Ok contents ->
         let files, dirs =
           Fs_memo.Dir_contents.to_list contents
           |> List.rev_filter_partition_map ~f:(fun (name, kind) ->
             let name_s = Filename.to_string name in
             match kind with
             | Unix.S_DIR ->
               (match name_s with
                | ".hg" | ".git" | "_darcs" | "_opam" | "_build" | "_esy" -> Skip
                | _ -> Right name)
             | _ ->
               let path = Path.External.relative_fname dir name |> Path.external_ in
               if String.starts_with ~prefix:".#" name_s || Path.is_broken_symlink path
               then Skip
               else Left name)
         in
         Ok (Some (Filename.Array.Set.of_list files, Filename.Array.Set.of_list dirs)))
  ;;
end

module Mount = struct
  type t =
    { loc : Loc.t
    ; logical_root : Path.Build.t
    ; backing_root : Backing.t
    }
end

module File = struct
  type t =
    | Workspace of Path.Source.t
    | Mounted of
        { mount : Mount.t
        ; logical : Path.Build.t
        ; backing : Backing.t
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
    | Mounted { backing; _ } -> Backing.path backing
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
        ; backing = Backing.parent_exn backing
        }
  ;;

  let relative t loc path =
    match t with
    | Workspace dir -> Workspace (Path.Source.relative ~error_loc:loc dir path)
    | Mounted { mount; logical; backing = _ } ->
      let { Mount.logical_root; backing_root; loc = _ } = mount in
      let local =
        match
          Option.bind (Path.Local_gen.descendant logical ~of_:logical_root) ~f:(fun l ->
            Path.Local.relative_result l path |> Result.to_option)
        with
        | Some local -> local
        | None ->
          User_error.raise
            ~loc
            [ Pp.textf "Included path %S is outside the mounted source tree." path ]
      in
      Mounted
        { mount
        ; logical = Path.Build.append_local logical_root local
        ; backing = Backing.append_local backing_root local
        }
  ;;

  let exists = function
    | Workspace path -> Fs_memo.file_exists (Path.Outside_build_dir.In_source_dir path)
    | Mounted { backing = Build _ as backing; _ } -> Backing.file_exists backing
    | Mounted { mount; logical; backing = External _ as file } ->
      let local =
        match Path.Local_gen.descendant logical ~of_:mount.logical_root with
        | Some local -> local
        | None ->
          Code_error.raise
            "Mounted file is outside its logical root"
            [ "file", Path.Build.to_dyn logical ]
      in
      (* Resolve parent directories through the inventory, not through links. *)
      let rec lookup directory = function
        | [] -> Memo.return false
        | name :: rest ->
          let* contents = Backing.dir_contents directory in
          (match contents with
           | Error _ | Ok None -> Memo.return false
           | Ok (Some (files, dirs)) ->
             (match rest with
              | [] ->
                if Filename.Array.Set.mem files name
                then Backing.file_exists file
                else Memo.return false
              | _ ->
                if Filename.Array.Set.mem dirs name
                then lookup (Backing.relative_fname directory name) rest
                else Memo.return false))
      in
      lookup mount.backing_root (Path.Local.explode local)
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
        | Mounted { backing; _ } -> Backing.read_file backing
      in
      Some contents
  ;;

  let equal a b =
    match a, b with
    | Workspace a, Workspace b -> Path.Source.equal a b
    | Mounted a, Mounted b ->
      Path.Build.equal a.logical b.logical && Backing.equal a.backing b.backing
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

  let mounted ~loc ~logical_root ~backing_root =
    File.mounted
      ~mount:{ Mount.loc; logical_root; backing_root }
      ~logical:logical_root
      ~backing:backing_root
  ;;

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
        ~backing:(Backing.relative_fname backing filename)
  ;;

  let append_local t local =
    match t with
    | Workspace path -> Workspace (Path.Source.append_local path local)
    | Mounted { mount; logical; backing } ->
      Mounted
        { mount
        ; logical = Path.Build.append_local logical local
        ; backing = Backing.append_local backing local
        }
  ;;

  let contents = function
    | Workspace path ->
      Dir_contents.of_source_path path
      >>| (function
       | Ok dir -> dir
       | Error _ -> Dir_contents.empty)
    | Mounted { mount; backing; _ } ->
      Backing.dir_contents backing
      >>| (function
       | Ok None -> Dir_contents.empty
       | Ok (Some (files, dirs)) -> Dir_contents.of_names ~files ~dirs
       | Error error ->
         User_error.raise
           ~loc:mount.loc
           [ Pp.textf
               "Unable to read %s"
               (Path.to_string_maybe_quoted (Backing.path backing))
           ; Unix_error.Detailed.pp error
           ])
  ;;
end
