open Import
module Rule_shell = Build_system.Rule_shell

let doc = "Open a shell in the prepared environment of a rule action."

let man =
  [ `S "DESCRIPTION"
  ; `P
      {|$(b,dune shell TARGET) resolves one concrete target to its rule, builds the
         rule's dependencies, and opens a shell in the exact execution location and
         sandbox mode selected for its action.|}
  ; `P
      {|A command after $(b,--) is executed instead of an interactive shell. The
         command receives the same prepared environment and working directory.|}
  ; `Blocks Common.help_secs
  ]
;;

let info = Cmd.info "shell" ~doc ~man

let resolved_program ~env ~dir program =
  match Filename.analyze_program_name program with
  | Absolute -> Path.of_string program
  | Relative_to_current_dir -> Path.relative dir program
  | In_path ->
    let path =
      match Env.get env Env_path.var with
      | None -> []
      | Some value ->
        Bin.parse value
        |> List.map ~f:(fun entry ->
          if String.is_empty entry
          then dir
          else if Filename.is_relative entry
          then Path.relative dir entry
          else Path.of_string entry)
    in
    (match Bin.which ~path program with
     | Some path -> path
     | None ->
       User_error.raise
         [ Pp.textf "Program %S was not found in the prepared PATH." program ])
;;

module Metadata_codec = struct
  module Conv = Stdune.Conv

  let strings = Conv.(list string)

  let env =
    Conv.iso strings (fun entries -> Env.of_unix (Array.of_list entries)) Env.to_unix
  ;;

  let targets =
    let to_ (file_paths, dir_paths) =
      Result.try_with (fun () ->
        let paths paths =
          List.map paths ~f:Path.Build.of_string |> Path.Build.Set.of_list
        in
        match
          Targets.create ~files:(paths file_paths) ~dirs:(paths dir_paths)
          |> Targets.validate
        with
        | Valid targets -> targets
        | No_targets
        | Inconsistent_parent_dir
        | File_and_directory_target_with_the_same_name _ ->
          Code_error.raise "invalid dune shell targets" [])
    in
    let from targets =
      let payload path = Path.Build.local path |> Path.Local.to_string in
      let files = ref [] in
      let dirs = ref [] in
      Targets.Validated.iter
        targets
        ~file:(fun path -> files := payload path :: !files)
        ~dir:(fun path -> dirs := payload path :: !dirs);
      List.rev !files, List.rev !dirs
    in
    Conv.iso_result Conv.(pair strings strings) to_ from
  ;;

  module Session = struct
    type t =
      { workspace_root : string
      ; build_dir : string
      ; cwd : string
      ; session_root : string
      ; dune_binary : string
      ; invocation_env : Env.t
      ; action_env : Env.t
      ; diff_command : string option
      ; targets : Targets.Validated.t
      ; use_sandbox_policy : bool
      }

    let codec =
      let open Conv in
      record
        (Record.make
           (fun
               workspace_root
                build_dir
                cwd
                session_root
                dune_binary
                invocation_env
                action_env
                diff_command
                targets
                use_sandbox_policy
              ->
              { workspace_root
              ; build_dir
              ; cwd
              ; session_root
              ; dune_binary
              ; invocation_env
              ; action_env
              ; diff_command
              ; targets
              ; use_sandbox_policy
              })
         |> Record.field
              "workspace-root"
              (required string)
              ~get:(fun { workspace_root; _ } -> workspace_root)
         |> Record.field "build-dir" (required string) ~get:(fun { build_dir; _ } ->
           build_dir)
         |> Record.field "cwd" (required string) ~get:(fun { cwd; _ } -> cwd)
         |> Record.field "session-root" (required string) ~get:(fun { session_root; _ } ->
           session_root)
         |> Record.field "dune-binary" (required string) ~get:(fun { dune_binary; _ } ->
           dune_binary)
         |> Record.field
              "invocation-env"
              (required env)
              ~get:(fun { invocation_env; _ } -> invocation_env)
         |> Record.field "action-env" (required env) ~get:(fun { action_env; _ } ->
           action_env)
         |> Record.field "diff-command" (optional string) ~get:(fun { diff_command; _ } ->
           diff_command)
         |> Record.field "targets" (required targets) ~get:(fun { targets; _ } -> targets)
         |> Record.field
              "sandbox-policy"
              (required (enum [ "enabled", true; "disabled", false ]))
              ~get:(fun { use_sandbox_policy; _ } -> use_sandbox_policy)
         |> Record.finish)
    ;;
  end

  let write path codec value =
    Conv.to_sexp codec value |> Csexp.to_string |> Io.write_file_exn path
  ;;

  let read path codec ~description =
    let invalid details =
      User_error.raise
        ~loc:(Loc.in_file path)
        (Pp.textf "Invalid %s in dune shell metadata." description :: details)
    in
    match Csexp.parse_string (Io.read_file_exn path) with
    | Error _ -> invalid []
    | Ok sexp ->
      (match Conv.of_sexp codec ~version:(0, 0) sexp with
       | Ok value -> value
       | Error error -> invalid [ Pp.text (Dyn.to_string (Conv.dyn_of_error error)) ])
  ;;
end

let dune_binary () = Util.dune_executable () |> Path.to_absolute_filename

let write_exact metadata name value =
  Io.write_file_exn (Path.relative metadata name) value
;;

let build_path_payload path = Path.Build.local path |> Path.Local.to_string

let write_runner metadata_dir =
  let quote = String.quote_for_shell in
  let command =
    [ dune_binary (); "internal"; "shell-replay"; Path.to_absolute_filename metadata_dir ]
    |> List.map ~f:quote
    |> String.concat ~sep:" "
  in
  let contents = sprintf "#!/bin/sh\nexec %s\n" command in
  List.iter [ "dune-run"; "run" ] ~f:(fun name ->
    Io.write_file_exn
      (Path.relative metadata_dir name)
      contents
      ~perm:Permissions.Mode.executable_file)
;;

let mode_note = function
  | None ->
    "sandbox mode none: this is the real _build directory; commands and run write there \
     directly."
  | Some Sandbox_mode.Copy ->
    "sandbox mode copy: this is the action's canonical digest sandbox, destroyed when \
     the session ends."
  | Some Sandbox_mode.Symlink ->
    "sandbox mode symlink: dependencies may point at shared build artifacts."
  | Some Sandbox_mode.Hardlink ->
    "sandbox mode hardlink: writes may affect shared build artifacts."
  | Some Sandbox_mode.Patch_back_source_tree ->
    Code_error.raise "patch-back dune shell should have been rejected" []
;;

(* The session helper commands are bash functions sourced into the interactive
   shell. They read the files written under [$DUNE_SHELL]. The help screen also
   shows the consequential differences from a real action execution. *)
let write_shell_init metadata ~mode ~has_direct_process_metadata =
  let init = Path.relative metadata "init.bash" in
  let command_fn, command_help =
    if has_direct_process_metadata
    then
      ( {|show_command () {
  cat "$DUNE_SHELL/command"
}

|}
      , "  show_command   print the exact direct program, args, and env\n" )
    else "", ""
  in
  let notes =
    String.concat
      ~sep:"\n"
      [ mode_note mode
      ; "This is not an isolation boundary; commands can modify your source tree."
      ; "run clears the action's declared targets, keeping live working directories, and \
         replays only the action; it does not rebuild dependencies or pick up edits made \
         after entry."
      ]
  in
  let contents =
    sprintf
      {|# Loaded into the dune shell session. Passing --rcfile skips the user's
# ~/.bashrc, so load it here to keep their normal environment, then define
# the session helper commands on top and show the help screen.
if [ -f "$HOME/.bashrc" ]; then . "$HOME/.bashrc"; fi

run () {
  "$DUNE_SHELL/dune-run" "$@"
}

show_action () {
  cat "$DUNE_SHELL/action.sexp"
}

%shelp () {
  cat <<'HELP'
dune shell session commands:
  run            replay the prepared action
  show_action    print or edit the expanded action ($DUNE_SHELL/action.sexp)
%s  help           show this message

%s
HELP
}

help
|}
      command_fn
      command_help
      notes
  in
  Io.write_file_exn init contents;
  init
;;

(* The leading wrappers the action interpreter executes before the action's
   "body": [Chdir] and [Setenv] determine the working directory and
   environment the body runs in, while the remaining wrappers only affect the
   body's streams or failure handling. Single-element [Progn]s are
   transparent. Returns the body together with the directory and environment
   in effect at that point. *)
let rec leading_context action ~dir ~env =
  match action with
  | Action.Chdir (dir, action) -> leading_context action ~dir ~env
  | Setenv (var, value, action) ->
    leading_context action ~dir ~env:(Env.add env ~var:(Env.Var.of_string var) ~value)
  | With_accepted_exit_codes (_, action)
  | Redirect_out (_, _, _, action)
  | Redirect_in (_, _, action)
  | Ignore (_, action)
  | Progn [ action ] -> leading_context action ~dir ~env
  | _ -> action, dir, env
;;

let bash = lazy (Bin.which ~path:(Env_path.path Env.initial) "bash")

let write_direct_process_metadata (action : Action.t) ~dir ~env metadata =
  let command =
    match action with
    | Run { prog = Ok program; args; can_run_in_action_runner = _ } ->
      Some (program, Appendable_list.to_list args)
    | Run { prog = Error _; _ } -> None
    | Bash { script; can_run_in_action_runner = _ } ->
      Option.map (Lazy.force bash) ~f:(fun program ->
        program, [ "-e"; "-u"; "-o"; "pipefail"; "-c"; script ])
    | _ -> None
  in
  match command with
  | None -> false
  | Some (program, args) ->
    let argv = Path.to_absolute_filename program :: args in
    Metadata_codec.write
      (Path.relative metadata "command.argv.csexp")
      Metadata_codec.strings
      argv;
    Metadata_codec.write
      (Path.relative metadata "command.env.csexp")
      Metadata_codec.env
      env;
    write_exact metadata "command.cwd" (Path.to_absolute_filename dir);
    Io.write_lines (Path.relative metadata "command.env") (Env.to_unix env);
    List.map argv ~f:String.quote_for_shell
    |> String.concat ~sep:" "
    |> write_exact metadata "command";
    true
;;

let write_metadata (shell : Rule_shell.t) ~body ~dir ~shell_env ~metadata =
  let metadata_absolute = Path.to_absolute_filename metadata in
  let env =
    shell_env
    |> Env.add ~var:(Env.Var.of_string "DUNE_SHELL") ~value:metadata_absolute
    |> Env_path.cons ~dir:metadata
  in
  let action_contents =
    Dune_rules.Action_for_shell.encode shell.action ~dir
    |> Dune_lang.pp
    |> Format.asprintf "%a\n" Pp.to_fmt
  in
  Io.write_file_exn (Path.relative metadata "action.sexp") action_contents;
  Io.write_file_exn
    (Path.relative metadata "rule-digest")
    (Digest.to_string shell.rule_digest ^ "\n");
  Io.write_file_exn
    (Path.relative metadata "sandbox")
    ((match shell.sandbox_dir with
      | None -> "none"
      | Some dir -> Path.to_absolute_filename (Path.build dir))
     ^ "\n");
  Io.write_file_exn
    (Path.relative metadata "sandbox-mode")
    (Sandbox_mode.to_string shell.sandbox_mode ^ "\n");
  let cwd = Path.as_in_build_dir_exn dir in
  let session_root = Option.value shell.sandbox_dir ~default:Path.Build.root in
  Metadata_codec.write
    (Path.relative metadata "session.csexp")
    Metadata_codec.Session.codec
    { Metadata_codec.Session.workspace_root = Path.to_absolute_filename Path.root
    ; build_dir = Path.to_absolute_filename Path.build_dir
    ; cwd = build_path_payload cwd
    ; session_root = build_path_payload session_root
    ; dune_binary = dune_binary ()
    ; invocation_env = Env.initial
    ; action_env = shell.env
    ; diff_command = !Clflags.diff_command
    ; targets = shell.targets
    ; use_sandbox_policy = shell.use_sandbox_policy
    };
  let has_direct_process_metadata =
    write_direct_process_metadata body ~dir ~env:shell_env metadata
  in
  write_runner metadata;
  env, has_direct_process_metadata
;;

let resolve_rule ~target common =
  let open Memo.O in
  let* setup = Util.setup () in
  let* requests =
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
  let path =
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

let locate_bash () =
  match Lazy.force bash with
  | Some bash -> bash
  | None ->
    User_error.raise
      [ Pp.text "dune shell requires bash to open an interactive session."
      ; Pp.text "Install bash, or use `dune shell TARGET -- COMMAND` to run a command."
      ]
;;

let run_in_rule_shell ~target ~command common =
  Build_system.run_exn (fun () ->
    let open Memo.O in
    let* rule = resolve_rule ~target common in
    Rule_shell.with_ rule ~f:(fun shell ->
      let body, dir, shell_env =
        leading_context shell.action ~dir:shell.dir ~env:shell.env
      in
      let shell_env =
        Dune_engine.Dtemp.add_to_env shell_env ~purpose:(Build_job (Some shell.targets))
      in
      let metadata =
        Temp.create
          ~perms:(Permissions.Mode.create ~user:Permissions.(read + write + execute) ())
          Dir
          ~prefix:"dune-shell"
          ~suffix:"session"
      in
      Fiber.finalize
        ~finally:(fun () ->
          Temp.destroy Dir metadata;
          Fiber.return ())
        (fun () ->
           let env, has_direct_process_metadata =
             write_metadata shell ~body ~dir ~shell_env ~metadata
           in
           (* Startup prints nothing from Dune itself. In an interactive session
              the sourced [init.bash] shows the help screen; in command mode the
              output belongs entirely to the user's command. *)
           let program, args =
             match command with
             | [] ->
               let init =
                 write_shell_init
                   metadata
                   ~mode:shell.sandbox_mode
                   ~has_direct_process_metadata
                 |> Path.to_absolute_filename
               in
               locate_bash (), [ "--rcfile"; init ]
             | program :: args -> resolved_program ~env ~dir program, args
           in
           Console.Status_line.clear ();
           let metadata =
             Dune_engine.Process_metadata.create
               ~purpose:(Build_job (Some shell.targets))
               ~can_run_in_action_runner:false
               ()
           in
           Dune_engine.Process.run_inherit_std_in_out_raw ~dir ~env ~metadata program args
           |> Fiber.map ~f:Dune_engine.Process.Failure_mode.exit_code_of_raw_status)))
;;

let term =
  let+ builder = Common.Builder.term
  and+ target = Arg.(required & pos 0 (some dep) None & info [] ~docv:"TARGET" ~doc:None)
  and+ command =
    Arg.(value & pos_right 0 string [] & info [] ~docv:"COMMAND" ~doc:None)
  in
  if Sys.win32
  then
    User_error.raise
      [ Pp.text "dune shell does not support native Windows yet."
      ; Pp.text "The replay runner currently requires a POSIX shell."
      ];
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
;;

module Internal_replay = struct
  let read_session metadata =
    Metadata_codec.read
      (Path.relative metadata "session.csexp")
      Metadata_codec.Session.codec
      ~description:"session data"
  ;;

  let initialize_paths ~workspace_root ~build_dir =
    Path.set_root (Path.External.of_string workspace_root);
    Path.Build.set_build_dir (Path.Outside_build_dir.of_string build_dir)
  ;;

  let clear_targets targets ~dir =
    let cwd =
      Path.of_filename_relative_to_initial_cwd "." |> Path.Expert.try_localize_external
    in
    let rec clear path =
      match Path.lstat path with
      | Ok { Unix.st_kind = S_DIR; st_perm; _ }
        when List.exists [ dir; cwd ] ~f:(fun cwd ->
               Path.equal path cwd || Path.is_descendant cwd ~of_:path) ->
        (* Recreating a pathname cannot repair another process's deleted cwd.
           Keep its directory inode and ancestors, without following symlinks. *)
        Unix.chmod (Path.to_string path) (st_perm lor 0o700);
        (match Path.readdir_unsorted path with
         | Ok entries ->
           List.iter entries ~f:(fun name -> clear (Path.relative_fname path name))
         | Error error -> Unix_error.Detailed.raise error)
      | Ok _ | Error _ -> Path.rm_rf ~chmod:true path
    in
    let clear path = clear (Path.build path) in
    Targets.Validated.iter targets ~file:clear ~dir:clear
  ;;

  let command =
    let info = Cmd.info "shell-replay" ~doc:"Replay a prepared dune shell action." in
    let term =
      let+ metadata =
        Arg.(
          required
          & pos 0 (some string) None
          & info [] ~docv:"SESSION" ~doc:(Some "dune shell metadata directory"))
      and+ environment_restored =
        Arg.(value & flag & info [ "environment-restored" ] ~doc:None)
      in
      let metadata = Path.of_filename_relative_to_initial_cwd metadata in
      let { Metadata_codec.Session.workspace_root
          ; build_dir
          ; cwd
          ; session_root
          ; dune_binary
          ; invocation_env
          ; action_env
          ; diff_command
          ; targets
          ; use_sandbox_policy
          }
        =
        read_session metadata
      in
      if not environment_restored
      then
        Proc.restore_cwd_and_execve
          dune_binary
          [ "internal"
          ; "shell-replay"
          ; "--environment-restored"
          ; Path.to_absolute_filename metadata
          ]
          ~env:invocation_env
      else (
        initialize_paths ~workspace_root ~build_dir;
        let config = Dune_config_file.Dune_config.default in
        Dune_config.init config ~watch:false;
        Clflags.diff_command := diff_command;
        Log.init No_log_file;
        let action_path = Path.relative metadata "action.sexp" in
        let dir = Path.Build.of_string cwd |> Path.build in
        let session_root = Path.Build.of_string session_root |> Path.build in
        let temp_dir =
          match Env.get action_env Env.Var.temp_dir with
          | Some temp_dir -> Path.of_string temp_dir
          | None ->
            User_error.raise
              ~loc:(Loc.in_file (Path.relative metadata "session.csexp"))
              [ Pp.text "No temporary directory in the dune shell action environment." ]
        in
        let action =
          let ast =
            Dune_lang.Parser.parse_string
              (Io.read_file_exn action_path)
              ~fname:(Path.to_string action_path)
              ~mode:Single
          in
          Dune_lang.Decoder.parse
            (Dune_rules.Action_for_shell.decode ~session_root ~dir)
            Univ_map.empty
            ast
        in
        let exit_code =
          Scheduler_setup.no_build_no_rpc ~config (fun () ->
            clear_targets targets ~dir;
            Dune_engine.Action_exec.replay
              { targets
              ; dir
              ; env = action_env
              ; rule_loc = Loc.in_file action_path
              ; action
              ; temp_dir
              ; sandbox_policy_root =
                  (if use_sandbox_policy then Some session_root else None)
              })
        in
        if exit_code <> 0
        then (
          Console.finish ();
          exit exit_code))
    in
    Cmd.v info term
  ;;
end

let command = Cmd.v info term
