open Import
open Fiber.O

(* Truncate to a short prefix for context naming, but stretch the prefix
   if two revs share the same prefix. *)
let short_with_dedup revs =
  let initial_prefix = 12 in
  let rev_id v = Dune_vcs.Vcs_tree.rev_id v in
  let rec stretch prefix =
    let names =
      List.map revs ~f:(fun v ->
        let id = rev_id v in
        let n = min prefix (String.length id) in
        String.sub id ~pos:0 ~len:n, v)
    in
    let unique =
      List.fold_left names ~init:String.Set.empty ~f:(fun s (n, _) -> String.Set.add s n)
    in
    if String.Set.cardinal unique = List.length names || prefix >= 40
    then names
    else stretch (prefix + 4)
  in
  stretch initial_prefix
;;

(* Resolve a list of [--rev] arg strings against the VCS at CWD, dedupe
   by rev_id, build [(Context_name.t, Vcs_tree.t)] pairs ready for
   Workspace.set_synthesised_for_revs. *)
let resolve ~revs =
  let* () = Fiber.return () in
  let cwd = Path.of_string (Sys.getcwd ()) in
  match Dune_vcs.Vcs.find_repo_root cwd with
  | None ->
    User_error.raise
      [ Pp.textf
          "--rev requires a VCS repository but none was found above %s."
          (Path.to_string_maybe_quoted cwd)
      ]
  | Some vcs ->
    let+ vcs_trees =
      Fiber.parallel_map revs ~f:(fun rev -> Dune_vcs.Vcs_tree.resolve_set vcs ~rev)
      >>| List.concat
    in
    let deduped =
      List.fold_left vcs_trees ~init:(String.Set.empty, []) ~f:(fun (seen, acc) v ->
        let id = Dune_vcs.Vcs_tree.rev_id v in
        if String.Set.mem seen id then seen, acc else String.Set.add seen id, v :: acc)
      |> snd
      |> List.rev
    in
    let with_names = short_with_dedup deduped in
    List.map with_names ~f:(fun (short, v) ->
      let name =
        Dune_engine.Context_name.parse_string_exn (Loc.none, sprintf "default-%s" short)
      in
      name, v)
;;
