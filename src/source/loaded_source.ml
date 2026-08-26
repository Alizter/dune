open Import
open Memo.O

type t =
  { snapshot : Dune_pkg.Source_snapshot.t
  ; root : Path.Build.t
  }

let create ~snapshot ~root = { snapshot; root }
let root t = t.root
let id t = Dune_pkg.Source_snapshot.id t.snapshot
let manifest_digest t = Dune_pkg.Source_snapshot.manifest_digest t.snapshot
let equal a b = Path.Build.equal a.root b.root && Dune_digest.equal (id a) (id b)
let source_path t path = Path.Build.append_local t.root path
let local_path t path = Path.drop_prefix (Path.build path) ~prefix:(Path.build t.root)
let readdir t path = Dune_pkg.Source_snapshot.readdir t.snapshot path
let read_file t path = Dune_pkg.Source_snapshot.read_file t.snapshot path
let file_path t path = Dune_pkg.Source_snapshot.file_path t.snapshot path

let file_exists t path =
  if Path.Local.is_root path
  then Memo.return true
  else (
    let basename = Path.Local.basename path in
    let parent = Path.Local.parent_exn path in
    let+ entries = readdir t parent in
    Filename.Map.mem entries basename)
;;

let diagnostic_name t path = source_path t path |> Path.Build.to_string

let to_dyn t =
  Dyn.record [ "snapshot", Dune_digest.to_dyn (id t); "root", Path.Build.to_dyn t.root ]
;;
