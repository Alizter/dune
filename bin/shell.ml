open Import
module Rule_shell = Build_system.Rule_shell
module Replay = Dune_engine.Action_exec.Replay
module Conv = Stdune.Conv

let write_runner metadata_dir =
  let command =
    ([ Path.to_absolute_filename (Util.dune_prog ())
     ; "internal"
     ; "shell-replay"
     ; "--workspace-root=" ^ Path.to_absolute_filename Path.root
     ; "--build-dir=" ^ Path.to_absolute_filename Path.build_dir
     ; Path.relative metadata_dir "replay.csexp" |> Path.to_absolute_filename
     ]
     @
     match !Clflags.diff_command with
     | None -> []
     | Some command -> [ "--diff-command=" ^ command ])
    |> List.map ~f:String.quote_for_shell
    |> String.concat ~sep:" "
  in
  let contents = sprintf "#!/bin/sh\nexec %s\n" command in
  List.iter [ "dune-run"; "run" ] ~f:(fun name ->
    Io.write_file_exn
      (Path.relative metadata_dir name)
      contents
      ~perm:Permissions.Mode.executable_file)
;;

(* The session helper commands are bash functions sourced into the interactive
   shell. They read the files written under [$DUNE_SHELL]. *)
let write_shell_init metadata =
  let init = Path.relative metadata "init.bash" in
  Io.write_file_exn
    init
    {|
# Loaded into the dune shell session. Passing --rcfile skips the user's
# ~/.bashrc, so load it here to keep their normal environment, then define
# the session helper commands on top and show the help screen.
if [ -f "$HOME/.bashrc" ]; then . "$HOME/.bashrc"; fi

run () {
  "$DUNE_SHELL/dune-run" "$@"
}

show_action () {
  cat "$DUNE_SHELL/action.sexp"
}

help () {
  cat <<'HELP'
dune shell session commands:
  run            replay the prepared action
  show_action    print the expanded action (inspection only)
  help           show this message
HELP
}

help
|};
  init
;;

let write_metadata { Rule_shell.action; replay; _ } ~dir ~env ~metadata =
  Print_rules.encode_action ~dir:(Path.build dir) action
  |> Dune_lang.pp
  |> Format.asprintf "%a\n" Pp.to_fmt
  |> Io.write_file_exn (Path.relative metadata "action.sexp");
  Conv.to_sexp Replay.conv replay
  |> Csexp.to_string
  |> Io.write_file_exn (Path.relative metadata "replay.csexp");
  write_runner metadata;
  Env.add
    env
    ~var:(Env.Var.of_string "DUNE_SHELL")
    ~value:(Path.to_absolute_filename metadata)
  |> Env_path.cons ~dir:metadata
;;

let resolve_rule ~target common =
  let open Memo.O in
  let* path =
    let+ requests =
      let* setup = Util.setup () in
      Target.resolve_targets_exn (Common.root common) setup [ target ]
      |> Action_builder.evaluate_and_collect_facts
      >>| fst
    in
    let paths =
      List.map requests ~f:(function
        | Target.Request.File path -> path
        | Alias _ ->
          User_error.raise
            [ Pp.text "dune shell requires a concrete file or directory target."
            ; Pp.text "Aliases select multiple actions and are not supported yet."
            ])
      |> Path.Set.of_list
    in
    match Path.Set.to_list paths with
    | [ path ] -> path
    | [] | _ :: _ :: _ ->
      User_error.raise [ Pp.text "dune shell requires exactly one concrete target." ]
  in
  Load_rules.get_rule path
  >>| function
  | Some rule -> rule
  | None ->
    User_error.raise
      [ Pp.textf "No rule produces %s." (Path.to_string_maybe_quoted path) ]
;;

let run_in_rule_shell ~target ~command common =
  Build_system.run_exn (fun () ->
    let open Memo.O in
    let* rule = resolve_rule ~target common in
    let { Dune_engine.Rule.targets; _ } = rule in
    Rule_shell.with_ rule ~f:(fun shell ->
      let { Rule_shell.sandbox; process_sandbox; env; session_dir; _ } = shell in
      let dir = Dune_engine.Sandbox.map_path sandbox targets.root in
      let env =
        let env = Dune_engine.Dtemp.add_to_env env ~purpose:(Build_job (Some targets)) in
        write_metadata shell ~dir ~env ~metadata:session_dir
      in
      (* Startup prints nothing from Dune itself. In an interactive session
         the sourced [init.bash] shows the help screen; in command mode the
         output belongs entirely to the user's command. *)
      let program, args =
        match command with
        | [] ->
          let init = write_shell_init session_dir |> Path.to_absolute_filename in
          let bash =
            let path = Env_path.path Env.initial in
            let dir = Path.of_string Fpath.initial_cwd in
            match Util.resolve_program ~path ~dir "bash" with
            | Some bash -> bash
            | None ->
              User_error.raise
                [ Pp.text "dune shell requires bash to open an interactive session."
                ; Pp.text
                    "Install bash, or use `dune shell TARGET -- COMMAND` to run a \
                     command."
                ]
          in
          bash, [ "--rcfile"; init ]
        | program :: args ->
          let path =
            match Env.get env Env_path.var with
            | None -> []
            | Some path -> List.map (Bin.parse path) ~f:(Path.relative (Path.build dir))
          in
          (match Util.resolve_program ~path ~dir:(Path.build dir) program with
           | Some program -> program, args
           | None ->
             User_error.raise
               [ Pp.textf "Program %S was not found in the prepared PATH." program ])
      in
      Console.Status_line.clear ();
      let metadata =
        Dune_engine.Process_metadata.create
          ~purpose:(Build_job (Some targets))
          ~can_run_in_action_runner:false
          ()
      in
      let open Fiber.O in
      let+ status =
        Dune_engine.Process.run_inherit_std_in_out_unreported
          ~sandbox:process_sandbox
          ~dir:(Path.build dir)
          ~env
          ~metadata
          program
          args
      in
      Dune_engine.Process.report_inherited_status
        ~dir:(Path.build dir)
        ~metadata
        program
        args
        status))
;;

let command =
  let info =
    let doc = "Open a shell in the prepared environment of a rule action." in
    let man =
      [ `S "DESCRIPTION"
      ; `P
          {|$(b,dune shell TARGET) opens a shell for debugging the action that builds
         TARGET. Dune builds the action's dependencies and prepares its environment,
         but does not execute the action itself.|}
      ; `P
          {|By default, $(b,dune shell TARGET) opens an interactive Bash session. Use
         $(b,dune shell TARGET -- COMMAND [ARGS...]) to run a command in the prepared
         environment instead.|}
      ; `P
          {|The shell or command starts in the directory containing the rule's targets,
         inside its sandbox if one is used. Directory and environment changes in the
         action are applied only when the action is run.|}
      ; `Blocks Common.help_secs
      ]
    in
    Cmd.info "shell" ~doc ~man
  in
  let term =
    let+ builder = Common.Builder.term
    and+ target =
      Arg.(required & pos 0 (some dep) None & info [] ~docv:"TARGET" ~doc:None)
    and+ command =
      Arg.(value & pos_right 0 string [] & info [] ~docv:"COMMAND" ~doc:None)
    in
    let common, config = Common.init_build builder in
    if Common.action_runner_requested common
    then
      User_error.raise
        [ Pp.text "dune shell does not support external action runners."
        ; Pp.text
            "The shell and replay cannot reproduce action-runner or sandbox-actions \
             process placement yet."
        ; Pp.text "Run dune shell again without those options."
        ];
    match Common.watch common with
    | Yes _ -> User_error.raise [ Pp.text "dune shell does not support watch mode." ]
    | No ->
      Global_lock.lock_exn ();
      let exit_code =
        Scheduler_setup.go_with_rpc_server ~common ~config (fun () ->
          run_in_rule_shell ~target ~command common)
      in
      if exit_code <> 0
      then (
        Console.finish ();
        exit exit_code)
  in
  Cmd.v info term
;;

module Internal_replay = struct
  let command =
    let info = Cmd.info "shell-replay" ~doc:"Replay a prepared dune shell action." in
    let term =
      let+ workspace_root =
        Arg.(
          required
          & opt (some string) None
          & info [ "workspace-root" ] ~docv:"DIR" ~doc:None)
      and+ build_dir =
        Arg.(
          required & opt (some string) None & info [ "build-dir" ] ~docv:"DIR" ~doc:None)
      and+ diff_command =
        Arg.(
          value
          & opt (some string) None
          & info [ "diff-command" ] ~docv:"COMMAND" ~doc:None)
      and+ snapshot =
        Arg.(required & pos 0 (some string) None & info [] ~docv:"SNAPSHOT" ~doc:None)
      in
      let replay =
        let path = Path.of_filename_relative_to_initial_cwd snapshot in
        match Csexp.parse_string (Io.read_file_exn path) with
        | Error (offset, message) ->
          Code_error.raise
            "malformed canonical s-expression"
            [ "path", Path.to_dyn path
            ; "offset", Dyn.int offset
            ; "message", Dyn.string message
            ]
        | Ok sexp ->
          (match Conv.of_sexp Replay.conv ~version:(0, 0) sexp with
           | Ok replay -> replay
           | Error error ->
             Code_error.raise
               "cannot decode prepared action"
               [ "path", Path.to_dyn path; "error", Conv.dyn_of_error error ])
      in
      Sys.chdir workspace_root;
      Path.set_root (Path.External.of_string workspace_root);
      Path.Build.set_build_dir (Path.Outside_build_dir.of_string build_dir);
      let config = Dune_config_file.Dune_config.default in
      Dune_config.init config ~watch:false;
      Clflags.diff_command := diff_command;
      Log.init No_log_file;
      Scheduler_setup.no_build_no_rpc ~config (fun () -> Replay.exec replay)
    in
    Cmd.v info term
  ;;
end
