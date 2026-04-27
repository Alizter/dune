open Import
open Memo.O

module Key : sig
  type encoded = Digest.t

  module Decoded : sig
    type t = private { packages : Package.Name.t list }

    val of_packages : Package.Name.t list -> t
  end

  val encode : Decoded.t -> encoded
  val decode : encoded -> Decoded.t
end = struct
  type encoded = Digest.t

  module Decoded = struct
    type t = { packages : Package.Name.t list }

    let equal x y = List.equal Package.Name.equal x.packages y.packages

    let to_string { packages } =
      String.enumerate_and (List.map packages ~f:Package.Name.to_string)
    ;;

    let of_packages packages =
      let packages = List.sort_uniq packages ~compare:Package.Name.compare in
      { packages }
    ;;
  end

  let reverse_table : (Digest.t, Decoded.t) Table.t = Table.create (module Digest) 128

  let encode ({ Decoded.packages } as x) =
    let y = Digest.repr Repr.(list Package.Name.repr) packages in
    match Table.find reverse_table y with
    | None ->
      Table.set reverse_table y x;
      y
    | Some x' ->
      if Decoded.equal x x'
      then y
      else
        Code_error.raise
          "Hash collision between sets of packages"
          [ "cached", Dyn.string (Decoded.to_string x')
          ; "new", Dyn.string (Decoded.to_string x)
          ]
  ;;

  let decode y =
    match Table.find reverse_table y with
    | Some x -> x
    | None ->
      Code_error.raise
        "unknown package set digest (encode was not called first)"
        [ "digest", Dyn.string (Digest.to_string y) ]
  ;;
end

let get_entries_fdecl
  : (Super_context.t -> Package.Name.t -> Install.Entry.Sourced.Unexpanded.t list Memo.t)
      Fdecl.t
  =
  Fdecl.create Dyn.opaque
;;

let set_entry_resolver f = Fdecl.set get_entries_fdecl f

let layout_dir (ctx : Build_context.t) ~key =
  Path.Build.relative ctx.build_dir (".install-layout/" ^ key)
;;

let compute_layout_entries_impl sctx layout_root packages =
  let get_entries = Fdecl.get get_entries_fdecl in
  let roots = Install.Roots.opam_from_prefix Path.root ~relative:Path.relative in
  Memo.parallel_map packages ~f:(fun pkg ->
    let install_paths = Install.Paths.make ~relative:Path.relative ~package:pkg ~roots in
    let+ entries = get_entries sctx pkg in
    List.filter_map entries ~f:(fun (s : Install.Entry.Sourced.Unexpanded.t) ->
      let entry = s.entry in
      match entry.kind with
      | Install.Entry.Unexpanded.Source_tree -> None
      | File | Directory ->
        let relative =
          Install.Entry.relative_installed_path entry ~paths:install_paths
          |> Path.as_in_source_tree_exn
        in
        let dst = Path.Build.append_source layout_root relative in
        Some (s, dst)))
  >>| List.rev_concat
;;

module Memo_input = struct
  type t = Context_name.t * Digest.t

  let equal (a1, b1) (a2, b2) = Context_name.equal a1 a2 && Digest.equal b1 b2
  let hash (a, b) = Tuple.T2.hash Context_name.hash Digest.hash (a, b)
  let to_dyn (a, b) = Dyn.pair Context_name.to_dyn Digest.to_dyn (a, b)
end

let compute_layout_entries =
  let memo =
    Memo.create
      "install-layout-entries"
      ~input:(module Memo_input)
      (fun (context_name, digest) ->
         let* sctx = Super_context.find_exn context_name in
         let build_context = Context.build_context (Super_context.context sctx) in
         let key = Digest.to_string digest in
         let layout_root = layout_dir build_context ~key in
         let { Key.Decoded.packages } = Key.decode digest in
         compute_layout_entries_impl sctx layout_root packages)
  in
  fun sctx digest -> Memo.exec memo (Context.name (Super_context.context sctx), digest)
;;

let encode_packages packages = Key.Decoded.of_packages packages |> Key.encode

let layout_files sctx packages =
  let digest = encode_packages packages in
  let+ entries = compute_layout_entries sctx digest in
  List.map entries ~f:(fun (_, dst) -> Path.build dst)
;;

let layout_lib_root sctx packages =
  let key = Digest.to_string (encode_packages packages) in
  let ctx = Context.build_context (Super_context.context sctx) in
  Path.Build.relative (layout_dir ctx ~key) "lib"
;;

let gen_rules sctx ~dir key =
  match Digest.from_hex key with
  | None -> User_error.raise [ Pp.textf "invalid install layout key %S" key ]
  | Some digest ->
    let* entries = compute_layout_entries sctx digest in
    Memo.parallel_iter entries ~f:(fun (s, dst) ->
      let rule_dir = Path.Build.parent_exn dst in
      if Path.Build.equal rule_dir dir
      then (
        let src = Path.build s.Install.Entry.Sourced.entry.src in
        let loc =
          match s.source with
          | User l -> l
          | Dune -> Loc.in_file src
        in
        Super_context.add_rule sctx ~dir ~loc (Action_builder.symlink ~src ~dst))
      else Memo.return ())
;;
