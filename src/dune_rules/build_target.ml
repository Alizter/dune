open Import
open Memo.O

type t =
  { file_paths : Path.Build.t list
  ; directory_paths : Path.Build.t list
  ; aliases : Alias.Name.t list
  }

let empty = { file_paths = []; directory_paths = []; aliases = [] }

let in_dir dir =
  let+ loaded = Load_rules.load_dir ~dir:(Path.build dir) in
  match loaded with
  | Load_rules.Loaded.Build { rules_here; aliases; _ } ->
    { file_paths = Path.Build.Map.keys rules_here.by_file_targets
    ; directory_paths = Path.Build.Map.keys rules_here.by_directory_targets
    ; aliases = Alias.Name.Map.keys aliases
    }
  | External _ | Source _ | Build_under_directory_target _ -> empty
;;

let direct_paths paths ~dir =
  List.filter paths ~f:(fun path -> Path.Build.equal (Path.Build.parent_exn path) dir)
;;

let direct_names paths ~dir = direct_paths paths ~dir |> List.map ~f:Path.Build.basename

let exclude_source_files paths =
  Memo.parallel_map paths ~f:(fun path ->
    match Path.Build.drop_build_context path with
    | None -> Memo.return (Some path)
    | Some source_path ->
      let+ exists =
        Path.source source_path |> Path.as_outside_build_dir_exn |> Fs_memo.file_exists
      in
      Option.some_if (not exists) path)
  >>| List.filter_opt
;;

let file_paths_excluding_sources { file_paths; _ } = exclude_source_files file_paths

let direct_files_excluding_sources { file_paths; _ } ~dir =
  let+ paths = direct_paths file_paths ~dir |> exclude_source_files in
  List.map paths ~f:Path.Build.basename
;;

let direct_files { file_paths; _ } ~dir = direct_names file_paths ~dir
let direct_directories { directory_paths; _ } ~dir = direct_names directory_paths ~dir
