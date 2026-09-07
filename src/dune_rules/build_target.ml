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

let completion_mode token =
  if String.starts_with token ~prefix:"@@"
  then Some "@@", String.drop token 2
  else if String.starts_with token ~prefix:"@"
  then Some "@", String.drop token 1
  else None, token
;;

type completion_kind =
  | Targets
  | Aliases

let rec completion_trie contexts kind source_dir =
  let source_path = Source_tree.Dir.path source_dir in
  let* listings =
    Memo.parallel_map contexts ~f:(fun context ->
      let dir = Path.Build.append_source (Context.build_dir context) source_path in
      let+ listing = in_dir dir in
      dir, listing)
  in
  let+ values, target_directories =
    match kind with
    | Aliases ->
      Memo.return
        ( List.concat_map listings ~f:(fun (_, { aliases; _ }) ->
            List.map aliases ~f:Alias.Name.to_string)
        , [] )
    | Targets ->
      let+ values =
        Memo.parallel_map listings ~f:(fun (dir, listing) ->
          let+ files = direct_files_excluding_sources listing ~dir in
          List.map files ~f:Filename.to_string)
      in
      ( List.concat values
      , List.concat_map listings ~f:(fun (dir, listing) ->
          direct_directories listing ~dir |> List.map ~f:Filename.to_string) )
  in
  let source_directories =
    Source_tree.Dir.sub_dirs source_dir
    |> Filename.Array.Map.to_list
    |> List.map ~f:(fun (name, sub_dir) ->
      let child =
        Memo.lazy_ ~name:"build-target-completion-directory" (fun () ->
          let* sub_dir = Source_tree.Dir.sub_dir_as_t sub_dir in
          completion_trie contexts kind sub_dir)
      in
      Filename.to_string name, Path_completion.expandable child)
  in
  let target_directories =
    List.map target_directories ~f:(fun name -> name, Path_completion.opaque)
  in
  Path_completion.create ~values ~directories:(source_directories @ target_directories)
;;

let candidates ~cwd ~token =
  let alias_marker, token = completion_mode token in
  let kind = if Option.is_some alias_marker then Aliases else Targets in
  let* { Main.contexts; _ } = Main.get () in
  let* root = Source_tree.root () in
  let* trie = completion_trie contexts kind root in
  let+ candidates = Path_completion.candidates trie ~cwd ~token in
  match alias_marker with
  | None -> candidates
  | Some marker -> List.map candidates ~f:(fun candidate -> marker ^ candidate)
;;
