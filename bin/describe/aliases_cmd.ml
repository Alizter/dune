open Import

let fetch_results (build_system : Dune_rules.Main.build_system) root
    (_dir : Path.t) =
  let open Action_builder.O in
  let+ alias_targets =
    let+ load_dir =
      Action_builder.List.map build_system.contexts ~f:(fun ctx ->
          let dir =
            Path.Build.append_source
              (Dune_engine.Context_name.build_dir (Context.name ctx))
              root
            |> Path.build
          in
          Action_builder.of_memo (Load_rules.load_dir ~dir))
    in
    List.fold_left load_dir ~init:Dune_engine.Alias.Name.Map.empty
      ~f:(fun acc x ->
        match (x : Load_rules.Loaded.t) with
        | Build build -> Dune_engine.Alias.Name.Map.superpose acc build.aliases
        | _ -> acc)
    |> Dune_engine.Alias.Name.Map.keys
  in
  List.map ~f:Dune_engine.Alias.Name.to_string alias_targets

let term = Ls_like_cmd.term fetch_results

let command =
  let doc = "Print aliases in a given directory. Works similalry to ls." in
  Cmd.v (Cmd.info "aliases" ~doc ~envs:Common.envs) term
