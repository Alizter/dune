open Import

type t =
  { project : Dune_project.t
  ; mounted_package : Package.Name.t option
  ; source_tree_root : Source_tree.Dir.t
  ; build_context : Build_context.t
  ; partition_root : Path.Build.t
  ; output_root : Path.Build.t
  ; stanza_mask : Package.Name.Set.t option
  }

let create
      ~project
      ~mounted_package
      ~source_tree_root
      ~build_context
      ~partition_root
      ~stanza_mask
  =
  let { Build_context.build_dir; _ } = build_context in
  let output_root =
    Source_tree.Dir.source_path source_tree_root |> Path.Build.append_local build_dir
  in
  { project
  ; mounted_package
  ; source_tree_root
  ; build_context
  ; partition_root
  ; output_root
  ; stanza_mask
  }
;;

let project t = t.project
let source_root t = Source_tree.Dir.source_path t.source_tree_root
let build_context t = t.build_context
let partition_root t = t.partition_root
let output_root t = t.output_root
let stanza_mask t = t.stanza_mask
let visible_packages t = Option.bind t.mounted_package ~f:(fun _ -> t.stanza_mask)

let vendored_warnings t =
  match t.mounted_package with
  | Some _ -> true
  | None ->
    (match Source_tree.Dir.status t.source_tree_root with
     | Vendored -> true
     | Normal | Data_only -> false)
;;

let visible_project t =
  match visible_packages t with
  | None -> t.project
  | Some packages ->
    Dune_project.filter_packages t.project ~f:(Package.Name.Set.mem packages)
;;

let owner t = t.mounted_package

let packages t =
  let packages = Dune_project.including_hidden_packages t.project in
  match visible_packages t with
  | None -> packages
  | Some visible ->
    Package.Name.Map.filteri packages ~f:(fun name _ -> Package.Name.Set.mem visible name)
;;

let output_path t source_path =
  let { Build_context.build_dir; _ } = t.build_context in
  Path.Build.append_local build_dir source_path
;;

let source_tree_dir t output_path =
  match Path.drop_prefix (Path.build output_path) ~prefix:(Path.build t.output_root) with
  | None -> Memo.return None
  | Some local -> Source_tree.Dir.find_dir t.source_tree_root local
;;
