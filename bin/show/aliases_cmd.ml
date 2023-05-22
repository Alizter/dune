open Import
open Stdune

let doc = "Print aliases in a given directory. Works similalry to ls."

let pp_aliases ~(contexts : Context.t list) path =
  let dir = Path.of_string path in
  let root =
    match (dir : Path.t) with
    | External e ->
      Code_error.raise "target_hint: external path"
        [ ("path", Path.External.to_dyn e) ]
    | In_source_tree d -> d
    | In_build_dir d -> (
      match Path.Build.drop_build_context d with
      | Some d -> d
      | None -> Path.Source.root)
  in
  let open Action_builder.O in
  let+ alias_targets =
    let+ load_dir =
      Action_builder.List.map contexts ~f:(fun ctx ->
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
        | Build build ->
          Dune_engine.Alias.Name.Map.union
            ~f:(fun _ a _ -> Some a)
            acc build.aliases
        | _ -> acc)
    |> Dune_engine.Alias.Name.Map.to_list_map ~f:(fun name _ ->
           Dune_engine.Alias.Name.to_string name)
  in
  [ Pp.textf "%s:" (Path.to_string dir)
  ; Pp.concat_map alias_targets ~f:Pp.text ~sep:Pp.newline
  ]
  |> Pp.concat ~sep:Pp.newline

let term =
  let+ common = Common.term
  and+ paths = Arg.(value & pos_all string [ "." ] & info [] ~docv:"DIR") in
  let config = Common.init common in
  let request (setup : Dune_rules.Main.build_system) =
    let open Action_builder.O in
    let+ paragraphs =
      Action_builder.List.map paths ~f:(pp_aliases ~contexts:setup.contexts)
    in
    paragraphs
    |> Pp.concat ~sep:(Pp.seq Pp.newline Pp.newline)
    |> List.singleton |> User_message.make |> User_message.print
  in
  Scheduler.go ~common ~config @@ fun () ->
  let open Fiber.O in
  let+ res = Build_cmd.run_build_system ~common ~request in
  match res with
  | Error `Already_reported -> raise Dune_util.Report_error.Already_reported
  | Ok () -> ()

let command = Cmd.v (Cmd.info "aliases" ~doc ~envs:Common.envs) term
