open Import

let fetch_results (_ : Dune_rules.Main.build_system) root dir =
  let open Action_builder.O in
  let+ targets =
    let open Memo.O in
    Target.all_direct_targets (Some root)
    >>| Path.Build.Map.to_list |> Action_builder.of_memo
  in
  List.map targets
    ~f:
      (if Path.is_in_build_dir dir then fun (path, k) -> (Path.build path, k)
      else fun (path, k) ->
        match Path.Build.extract_build_context path with
        | None -> (Path.build path, k)
        | Some (_, path) -> (Path.source path, k))
  |> (* Only suggest hints for the basename, otherwise it's slow when there
        are lots of files *)
  List.filter_map ~f:(fun (path, kind) ->
      match Path.equal (Path.parent_exn path) dir with
      | false -> None
      | true ->
        (* directory targets can be distinguied by the trailing path seperator *)
        Some
          (match kind with
          | Target.File -> Path.basename path
          | Directory -> Path.basename path ^ Filename.dir_sep))

let term = Ls_like_cmd.term fetch_results

let command =
  let doc = "Print targets in a given directory. Works similalry to ls." in
  Cmd.v (Cmd.info "targets" ~doc ~envs:Common.envs) term
