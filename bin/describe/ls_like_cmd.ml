open Import

let term fetch_results =
  let+ common = Common.term
  and+ paths = Arg.(value & pos_all string [ "." ] & info [] ~docv:"DIR") in
  let config = Common.init common in
  let request (build_system : Dune_rules.Main.build_system) =
    let header = List.length paths > 1 in
    let open Action_builder.O in
    let+ paragraphs =
      Action_builder.List.map paths ~f:(fun path ->
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
          let+ targets = fetch_results build_system root dir in
          (if header then [ Pp.textf "%s:" (Path.to_string dir) ] else [])
          @ [ Pp.concat_map targets ~f:Pp.text ~sep:Pp.newline ]
          |> Pp.concat ~sep:Pp.newline)
    in
    Console.print [ Pp.concat paragraphs ~sep:(Pp.seq Pp.newline Pp.newline) ]
  in
  Scheduler.go ~common ~config @@ fun () ->
  let open Fiber.O in
  Build_cmd.run_build_system ~common ~request
  >>| fun (_ : (unit, [ `Already_reported ]) result) -> ()
