open Import
open Memo.O

module Mounted_layer = struct
  type t =
    | Directory of
        { logical_root : Path.Build.t
        ; backing_root : Path.Build.t
        }
    | File of
        { logical : Path.Build.t
        ; backing : Path.Build.t
        }

  let directory ~logical_root ~backing_root = Directory { logical_root; backing_root }
  let file ~logical ~backing = File { logical; backing }

  let equal a b =
    match a, b with
    | ( Directory { logical_root; backing_root }
      , Directory { logical_root = logical_root'; backing_root = backing_root' } ) ->
      Path.Build.equal logical_root logical_root'
      && Path.Build.equal backing_root backing_root'
    | File { logical; backing }, File { logical = logical'; backing = backing' } ->
      Path.Build.equal logical logical' && Path.Build.equal backing backing'
    | Directory _, File _ | File _, Directory _ -> false
  ;;

  let hash = function
    | Directory { logical_root; backing_root } ->
      Tuple.T3.hash
        Int.hash
        Path.Build.hash
        Path.Build.hash
        (0, logical_root, backing_root)
    | File { logical; backing } ->
      Tuple.T3.hash Int.hash Path.Build.hash Path.Build.hash (1, logical, backing)
  ;;

  let to_dyn = function
    | Directory { logical_root; backing_root } ->
      Dyn.variant
        "Directory"
        [ Dyn.record
            [ "logical_root", Path.Build.to_dyn logical_root
            ; "backing_root", Path.Build.to_dyn backing_root
            ]
        ]
    | File { logical; backing } ->
      Dyn.variant
        "File"
        [ Dyn.record
            [ "logical", Path.Build.to_dyn logical; "backing", Path.Build.to_dyn backing ]
        ]
  ;;

  type resolution =
    | Candidate of
        { path : Path.Build.t
        ; blockers : Path.Build.t list
        }
    | Blocked
    | Unrelated

  let proper_ancestors path =
    let rec loop parent = function
      | [] | [ _ ] -> []
      | component :: rest ->
        let parent = Path.Local.relative_fname parent component in
        parent :: loop parent rest
    in
    loop Path.Local.root (Path.Local.explode path)
  ;;

  let resolve_file t logical =
    match t with
    | Directory { logical_root; backing_root } ->
      (match Path.drop_prefix (Path.build logical) ~prefix:(Path.build logical_root) with
       | None -> Unrelated
       | Some local ->
         Candidate
           { path = Path.Build.append_local backing_root local
           ; blockers =
               List.map (proper_ancestors local) ~f:(Path.Build.append_local backing_root)
           })
    | File { logical = layer_logical; backing } ->
      if Path.Build.equal logical layer_logical
      then Candidate { path = backing; blockers = [] }
      else if Path.is_descendant (Path.build logical) ~of_:(Path.build layer_logical)
      then Blocked
      else Unrelated
  ;;
end

module File = struct
  type mounted =
    { logical : Path.Build.t
    ; layers : Mounted_layer.t list
    }

  type t =
    | Workspace of Path.Source.t
    | Mounted of mounted

  let workspace path = Workspace path
  let mounted ~logical ~layers = Mounted { logical; layers }

  let source_path = function
    | Workspace path -> Source_path.workspace path
    | Mounted { logical; _ } -> Source_path.build logical
  ;;

  let path = function
    | Workspace path -> Path.source path
    | Mounted { logical; _ } -> Path.build logical
  ;;

  let find_backing_path { logical; layers } =
    let rec loop = function
      | [] -> Memo.return None
      | layer :: layers ->
        (match Mounted_layer.resolve_file layer logical with
         | Blocked -> Memo.return None
         | Unrelated -> loop layers
         | Candidate { path; blockers } ->
           let* exists = Build_system.file_exists (Path.build path) in
           if exists
           then Memo.return (Some (Path.build path))
           else
             let* blocked =
               Memo.List.exists blockers ~f:(fun path ->
                 Build_system.file_exists (Path.build path))
             in
             if blocked then Memo.return None else loop layers)
    in
    loop (List.rev layers)
  ;;

  let backing_path = function
    | Workspace path -> Memo.return (Path.source path)
    | Mounted mounted ->
      find_backing_path mounted
      >>| (function
       | Some path -> path
       | None ->
         Code_error.raise
           "Mounted source file has no backing input"
           [ "file", Path.Build.to_dyn mounted.logical
           ; "layers", Dyn.list Mounted_layer.to_dyn mounted.layers
           ])
  ;;

  let as_workspace = function
    | Workspace path -> Some path
    | Mounted _ -> None
  ;;

  let relative t loc path =
    match t with
    | Workspace file ->
      Path.Source.relative ~error_loc:loc (Path.Source.parent_exn file) path |> workspace
    | Mounted { logical; layers } ->
      mounted
        ~logical:(Path.Build.relative ~error_loc:loc (Path.Build.parent_exn logical) path)
        ~layers
  ;;

  let read = function
    | Workspace path ->
      let path = Path.Outside_build_dir.In_source_dir path in
      let* exists = Fs_memo.file_exists path in
      if exists then Fs_memo.file_contents path >>| Option.some else Memo.return None
    | Mounted mounted ->
      find_backing_path mounted
      >>= (function
       | None -> Memo.return None
       | Some path -> Build_system.read_file path >>| Option.some)
  ;;

  let equal a b =
    match a, b with
    | Workspace a, Workspace b -> Path.Source.equal a b
    | Mounted a, Mounted b ->
      Path.Build.equal a.logical b.logical
      && List.equal Mounted_layer.equal a.layers b.layers
    | Workspace _, Mounted _ | Mounted _, Workspace _ -> false
  ;;

  let diagnostic_name = function
    | Workspace path -> Path.Source.to_string path
    | Mounted { logical; _ } -> Path.Build.to_string logical
  ;;

  let to_dyn = function
    | Workspace path -> Dyn.variant "Workspace" [ Path.Source.to_dyn path ]
    | Mounted { logical; layers } ->
      Dyn.variant
        "Mounted"
        [ Dyn.record
            [ "logical", Path.Build.to_dyn logical
            ; "layers", Dyn.list Mounted_layer.to_dyn layers
            ]
        ]
  ;;
end

module Dir = struct
  type mounted =
    { logical : Path.Build.t
    ; backing : Path.Build.t
    ; layers : Mounted_layer.t list
    }

  type t =
    | Workspace of Path.Source.t
    | Mounted of mounted

  let workspace path = Workspace path
  let mounted ~logical ~backing ~layers = Mounted { logical; backing; layers }

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
    | Mounted { logical; layers; _ } ->
      File.mounted ~logical:(Path.Build.relative_fname logical filename) ~layers
  ;;
end
