open Import

type t =
  { project : Dune_project.t
  ; mounted_package : Package.Name.t option
  ; source_tree_root : Source_tree.Dir.t
  ; context : Context.t
  ; partition_root : Path.Build.t
  ; output_root : Path.Build.t
  ; stanza_mask : Package.Name.Set.t option
  }

let create
      ~project
      ~mounted_package
      ~source_tree_root
      ~context
      ~partition_root
      ~stanza_mask
  =
  let output_root =
    Source_tree.Dir.source_path source_tree_root
    |> Path.Build.append_local (Context.build_dir context)
  in
  { project
  ; mounted_package
  ; source_tree_root
  ; context
  ; partition_root
  ; output_root
  ; stanza_mask
  }
;;

let project t = t.project
let source_root t = Source_tree.Dir.source_path t.source_tree_root
let build_context t = Context.build_context t.context
let partition_root t = t.partition_root
let output_root t = t.output_root
let stanza_mask t = t.stanza_mask
let is_workspace t = Option.is_none t.mounted_package
let visible_packages t = if is_workspace t then None else t.stanza_mask

let vendored_warnings t =
  match t.mounted_package with
  | Some _ -> true
  | None ->
    (match Source_tree.Dir.status t.source_tree_root with
     | Vendored -> true
     | Normal | Data_only -> false)
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
  Path.Build.append_local (Context.build_dir t.context) source_path
;;

let source_tree_dir t output_path =
  match Path.drop_prefix (Path.build output_path) ~prefix:(Path.build t.output_root) with
  | None -> Memo.return None
  | Some local -> Source_tree.Dir.find_dir t.source_tree_root local
;;
