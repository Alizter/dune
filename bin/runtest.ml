open Import

let runtest_info =
  let doc = "Run tests." in
  let man =
    [ `S "DESCRIPTION"
    ; `P "Run the given tests. The [TEST] argument can be either:"
    ; `I
        ( "-"
        , "A directory: If a directory is provided, dune will recursively run all tests \
           within that directory." )
    ; `I
        ( "-"
        , "A file name: If a specific file name is provided, dune will run the tests \
           with that name." )
    ; `P
        "If no [TEST] is provided, dune will run all tests in the current directory and \
         its subdirectories."
    ; `P "See EXAMPLES below for additional information on use cases."
    ; `Blocks Common.help_secs
    ; Common.examples
        [ "Run all tests in a given directory", "dune runtest path/to/dir/"
        ; "Run a specific cram test", "dune runtest path/to/mytest.t"
        ; ( "Run all tests in the current source tree (including those that passed on \
             the last run)"
          , "dune runtest --force" )
        ; ( "Run tests sequentially without output buffering"
          , "dune runtest --no-buffer -j 1" )
        ; "Run tests in a specific build context", "dune runtest _build/my_context/"
        ]
    ]
  in
  Cmd.info "runtest" ~doc ~man ~envs:Common.envs
;;

let test_path_completion_func builder ~token =
  let candidates =
    match builder with
    | None -> []
    | Some builder ->
      (try
         let builder = Common.Builder.for_completion builder in
         let common, config = Common.init builder in
         let cwd =
           Path.of_filename_relative_to_initial_cwd Filename.current_dir_name
           |> Path.Expert.try_localize_external
           |> Path.as_in_source_tree
         in
         match cwd with
         | None -> []
         | Some cwd ->
           (match Global_lock.lock () with
            | Ok () ->
              Scheduler_setup.go_for_completion ~common ~config (fun () ->
                Build_system.run_exn (fun () ->
                  Dune_rules.Runtest_completion.candidates ~cwd ~token))
            | Error lock_held_by ->
              Scheduler_setup.go_for_completion ~common ~config (fun () ->
                Rpc.Rpc_common.fire_request
                  ~name:"runtest-completion"
                  ~wait:false
                  ~warn_forwarding:false
                  ~lock_held_by
                  builder
                  Dune_rpc_impl.Decl.runtest_completion
                  (Path.Source.to_string cwd, token)))
       with
       | User_error.E _ | Dune_rpc.Version_error.E _ | Dune_scheduler.Shutdown.E Timeout
         -> [])
  in
  Ok (List.map candidates ~f:Cmdliner.Arg.Completion.string)
;;

let test_path_conv : string Cmdliner.Arg.conv =
  let parser s = Ok s in
  let pp = Format.pp_print_string in
  let completion =
    Cmdliner.Arg.Completion.make ~context:Common.Builder.term test_path_completion_func
  in
  Cmdliner.Arg.Conv.make ~docv:"TEST" ~parser ~pp ~completion ()
;;

let runtest_term =
  (* CR-someday Alizter: document this option *)
  let name = Arg.info [] ~docv:"TEST" ~doc:None in
  let+ builder = Common.Builder.term
  and+ test_paths = Arg.(value & pos_all test_path_conv [ "." ] name) in
  let common, config = Common.init_build builder in
  match Global_lock.lock () with
  | Ok () ->
    Build.run_build_command ~common ~config ~request:(fun setup ->
      Runtest_common.make_request
        ~scontexts:setup.scontexts
        ~to_cwd:(Common.root common).to_cwd
        ~test_paths)
  | Error lock_held_by ->
    let test_paths =
      List.map test_paths ~f:(fun path ->
        let path =
          if Filename.is_relative path then Common.prefix_target common path else path
        in
        Path.relative Path.root path |> Path.to_string)
    in
    Scheduler_setup.no_build_no_rpc ~config (fun () ->
      let open Fiber.O in
      Rpc.Rpc_common.fire_request
        ~name:"runtest"
        ~wait:false
        ~lock_held_by
        builder
        Dune_rpc.Procedures.Public.runtest
        test_paths
      >>| Rpc.Rpc_common.wrap_build_outcome_exn ~print_on_success:true)
;;

let commands =
  let command = Cmd.v runtest_info runtest_term in
  [ command; Common.command_alias command runtest_term "test" ]
;;
