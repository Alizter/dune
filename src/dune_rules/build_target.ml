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

let direct_names paths ~dir =
  List.filter_map paths ~f:(fun path ->
    Option.some_if
      (Path.Build.equal (Path.Build.parent_exn path) dir)
      (Path.Build.basename path))
;;

let direct_files { file_paths; _ } ~dir = direct_names file_paths ~dir
let direct_directories { directory_paths; _ } ~dir = direct_names directory_paths ~dir
