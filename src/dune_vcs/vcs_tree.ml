open Stdune
open Fiber.O

(* Each tree node has its immediate children, classified as files or
   sub-dirs. Built once at resolve time by traversing the recursive
   ls-tree output. *)
type tree_node =
  { files : Filename.Set.t
  ; sub_dirs : Filename.Set.t
  }

let empty_node = { files = Filename.Set.empty; sub_dirs = Filename.Set.empty }

type t =
  { kind : Vcs.Kind.t
  ; root : Path.t
  ; rev_id : string
  ; tree : tree_node Path.Source.Map.t
  ; blob_shas : string Path.Source.Map.t
  ; files : Path.Source.t list
  }

let rev_id t = t.rev_id
let kind t = t.kind
let blob_sha t path = Path.Source.Map.find t.blob_shas path
let files t = t.files
let equal a b = Vcs.Kind.equal a.kind b.kind && String.equal a.rev_id b.rev_id

let hash t =
  let kind_tag =
    match t.kind with
    | Vcs.Kind.Git -> 0
    | Hg -> 1
  in
  Tuple.T2.hash Int.hash String.hash (kind_tag, t.rev_id)
;;

let to_dyn t =
  let kind_s =
    match t.kind with
    | Vcs.Kind.Git -> "Git"
    | Hg -> "Hg"
  in
  Dyn.record [ "kind", Dyn.string kind_s; "rev_id", Dyn.string t.rev_id ]
;;

let not_implemented kind =
  User_error.raise
    [ Pp.textf
        "Reading from a %s revision is not yet implemented. Only Git is currently \
         supported."
        (match kind with
         | Vcs.Kind.Hg -> "Mercurial"
         | Git -> "Git")
    ]
;;

(* Index a flat list of (Path.Local.t, sha) into a Path.Source.Map.t
   keyed by directory, with each value listing direct children. *)
let index_tree entries =
  List.fold_left entries ~init:Path.Source.Map.empty ~f:(fun acc (path, _sha) ->
    let local = path in
    let components = Path.Local.explode local in
    let rec record acc parent comps =
      match comps with
      | [] -> acc
      | [ basename ] ->
        Path.Source.Map.update acc parent ~f:(function
          | None -> Some { empty_node with files = Filename.Set.singleton basename }
          | Some node -> Some { node with files = Filename.Set.add node.files basename })
      | basename :: rest ->
        let acc =
          Path.Source.Map.update acc parent ~f:(function
            | None -> Some { empty_node with sub_dirs = Filename.Set.singleton basename }
            | Some node ->
              Some { node with sub_dirs = Filename.Set.add node.sub_dirs basename })
        in
        let next_parent = Path.Source.relative_fname parent basename in
        record acc next_parent rest
    in
    record acc Path.Source.root components)
;;

let resolve_git_set ~root ~rev =
  let git = Git_subprocess.create ~root in
  let* commits =
    let* single = Git_subprocess.rev_parse_single git rev in
    match single with
    | Some sha -> Fiber.return [ sha ]
    | None ->
      let* listed = Git_subprocess.rev_list git rev in
      (match listed with
       | Some shas when shas <> [] -> Fiber.return shas
       | _ ->
         User_error.raise
           [ Pp.textf
               "Could not resolve %S to any revision in %s"
               rev
               (Path.to_string root)
           ])
  in
  Fiber.parallel_map commits ~f:(fun sha ->
    let+ entries = Git_subprocess.ls_tree_recursive git ~commit:sha in
    let blob_shas =
      List.fold_left entries ~init:Path.Source.Map.empty ~f:(fun acc (path, blob_sha) ->
        Path.Source.Map.set acc (Path.Source.of_local path) blob_sha)
    in
    let files =
      List.map entries ~f:(fun (path, _) -> Path.Source.of_local path)
      |> List.sort ~compare:Path.Source.compare
    in
    { kind = Vcs.Kind.Git
    ; root
    ; rev_id = sha
    ; tree = index_tree entries
    ; blob_shas
    ; files
    })
;;

let resolve_set (vcs : Vcs.t) ~rev =
  match vcs.kind with
  | Git -> resolve_git_set ~root:vcs.root ~rev
  | Hg -> not_implemented vcs.kind
;;

let lookup_node t dir =
  match Path.Source.Map.find t.tree dir with
  | Some node -> node
  | None -> empty_node
;;

let list_dir t dir =
  let node = lookup_node t dir in
  let entries =
    let files = Filename.Set.to_list node.files |> List.map ~f:(fun fn -> `File fn) in
    let dirs = Filename.Set.to_list node.sub_dirs |> List.map ~f:(fun fn -> `Dir fn) in
    files @ dirs
  in
  Fiber.return entries
;;

let read_file t path =
  match t.kind with
  | Git ->
    let git = Git_subprocess.create ~root:t.root in
    let local = Path.Source.to_local path in
    Git_subprocess.cat_file_blob git ~commit:t.rev_id ~path:local
  | Hg -> not_implemented t.kind
;;
