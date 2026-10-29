open Import
open Stdune.Action_types
open Action_intf.Exec

module Exec_result = struct
  type ok = { dynamic_deps_stages : (Dep.Set.t * Dep.Facts.t) list }
  type t = (ok, Exn_with_backtrace.t list) Result.t

  let ok_exn (t : t) =
    match t with
    | Ok t -> Fiber.return t
    | Error errs -> Fiber.reraise_all errs
  ;;
end

open Fiber.O

exception Shell_replay_failed of Process.Failure_mode.raw_status

let exec_run ~(ectx : context) ~(eenv : env) ~can_run_in_action_runner prog args =
  let can_run_in_action_runner =
    match ectx.mode with
    | Build -> can_run_in_action_runner
    | Shell_replay -> false
  in
  let metadata = { ectx.metadata with can_run_in_action_runner } in
  let run failure_mode ~display =
    Process.run_with_array_args
      ~display
      failure_mode
      ~dir:eenv.working_dir
      ~env:eenv.env
      ~stdout_to:eenv.stdout_to
      ~stderr_to:eenv.stderr_to
      ~stdin_from:eenv.stdin_from
      ~metadata
      ?sandbox:ectx.sandbox
      prog
      args
  in
  match ectx.mode with
  | Build ->
    let+ (_ : (unit, int) result) =
      run (Accept eenv.exit_codes) ~display:!Clflags.display
    in
    ()
  | Shell_replay ->
    let+ (), status = run Return_raw ~display:Quiet in
    (match status with
     | Process.Failure_mode.Exited exit_code ->
       if not (Predicate.test eenv.exit_codes exit_code)
       then raise (Shell_replay_failed status)
     | Process.Failure_mode.Signaled _ -> raise (Shell_replay_failed status))
;;

let bash_exn =
  let bin = lazy (Bin.which ~path:(Env_path.path Env.initial) "bash") in
  fun ~loc ~needed_to ->
    match Lazy.force bin with
    | Some path -> path
    | None ->
      User_error.raise
        ~loc
        [ Pp.textf "I need bash to %s but I couldn't find it :(" needed_to ]
;;

let zero = Predicate_lang.element 0

let rec exec t ~ectx ~eenv : unit Fiber.t =
  match (t : Action.t) with
  | Run { prog = Error e; args = _; can_run_in_action_runner = _ } ->
    Action.Prog.Not_found.raise e
  | Run { prog = Ok prog; args; can_run_in_action_runner } ->
    let args = Appendable_list.to_immutable_array args in
    exec_run ~ectx ~eenv ~can_run_in_action_runner prog args
  | With_accepted_exit_codes (exit_codes, t) ->
    let eenv =
      let exit_codes =
        Predicate.create (Predicate_lang.test exit_codes ~test:Int.equal ~standard:zero)
      in
      { eenv with exit_codes }
    in
    exec t ~ectx ~eenv
  | Chdir (dir, t) -> exec t ~ectx ~eenv:{ eenv with working_dir = dir }
  | Setenv (var, value, t) ->
    exec
      t
      ~ectx
      ~eenv:{ eenv with env = Env.add eenv.env ~var:(Env.Var.of_string var) ~value }
  | Redirect_out (Stdout, fn, perm, Echo s) ->
    let perm = File_perm.to_unix_perm perm in
    Io.write_file_exn ~perm (Path.build fn) (String.concat s ~sep:" ");
    Fiber.return ()
  | Redirect_out (outputs, fn, perm, t) ->
    let fn = Path.build fn in
    redirect_out t ~ectx ~eenv outputs ~perm fn
  | Redirect_in (inputs, fn, t) -> redirect_in t ~ectx ~eenv inputs fn
  | Ignore (outputs, t) -> redirect_out t ~ectx ~eenv ~perm:Normal outputs Dev_null.path
  | Progn ts -> exec_list ts ~ectx ~eenv
  | Concurrent ts ->
    Fiber.parallel_iter ts ~f:(fun t ->
      let eenv =
        { eenv with
          stdout_to = Process.Io.multi_use eenv.stdout_to
        ; stderr_to = Process.Io.multi_use eenv.stderr_to
        ; stdin_from = Process.Io.multi_use eenv.stdin_from
        }
      in
      exec t ~ectx ~eenv)
  | Echo strs ->
    let () =
      String.concat strs ~sep:" " |> output_string (Process.Io.out_channel eenv.stdout_to)
    in
    Fiber.return ()
  | Cat xs ->
    List.iter xs ~f:(fun fn ->
      Io.with_file_in fn ~f:(fun ic ->
        Io.copy_channels ic (Process.Io.out_channel eenv.stdout_to)));
    Fiber.return ()
  | Copy (src, dst) ->
    let dst = Path.build dst in
    let copy_file ~src ~dst =
      Path.parent dst |> Option.iter ~f:Path.mkdir_p;
      Io.copy_file ~overwrite:true ~src ~dst ()
    in
    let mkdir ~src:_ ~dst = Path.mkdir_p dst in
    let on_unsupported ~src kind =
      User_error.raise
        [ Pp.textf
            "Failed to copy %s of kind %S while executing a copy action"
            (Path.to_string_maybe_quoted src)
            (File_kind.to_string_hum kind)
        ]
    in
    let () =
      (* NOTE(anmonteiro): we may reconsider relaxing the directory target
           constraint (see [test/blackbox-tests/test-cases/pkg/source-with-directory-symlink.t]).

           [Copy] stays file-oriented by default. We only use recursive copying
           when [dst] is a directory target. *)
      match ectx.metadata.purpose with
      | Build_job (Some { dirs; _ }) when Filename.Set.mem dirs (Path.basename dst) ->
        Tree_traversal.traverse ~src ~dst ~on_file:copy_file ~mkdir ~on_unsupported ()
      | _ -> copy_file ~src ~dst
    in
    Fiber.return ()
  | Symlink (src, dst) when Sys.win32 -> exec (Copy (src, dst)) ~ectx ~eenv
  | Symlink (src, dst) ->
    Io.portable_symlink ~overwrite:true ~src ~dst:(Path.build dst);
    Fiber.return ()
  | Hardlink (src, dst) ->
    Io.portable_hardlink ~overwrite:true ~src ~dst:(Path.build dst);
    Fiber.return ()
  | System command ->
    let prog, arg =
      Env_path.system_shell_exn ~needed_to:"interpret (system ...) actions"
    in
    exec_run
      ~ectx
      ~eenv
      ~can_run_in_action_runner:true
      prog
      (Array.Immutable.of_list [ arg; command ])
  | Bash { script; can_run_in_action_runner } ->
    exec_run
      ~ectx
      ~eenv
      ~can_run_in_action_runner
      (bash_exn ~loc:ectx.rule_loc ~needed_to:"interpret (bash ...) actions")
      (Array.Immutable.of_list [ "-e"; "-u"; "-o"; "pipefail"; "-c"; script ])
  | Write_file (fn, perm, s) ->
    let start = Time.now () in
    let fn = Path.build fn in
    let () =
      let perm = File_perm.to_unix_perm perm in
      Io.write_file_exn fn s ~perm
    in
    let finish = Time.now () in
    Dune_trace.emit ~buffered:true Action (fun () ->
      Dune_trace.Event.Action.write_file ~start ~finish ~file:fn ~size:(String.length s));
    Fiber.return ()
  | Rename (src, dst) ->
    let src = Path.Build.to_string src in
    let dst = Path.Build.to_string dst in
    Unix.rename src dst;
    Fiber.return ()
  | Remove_tree path ->
    Path.rm_rf (Path.build path);
    Fiber.return ()
  | Mkdir path ->
    Path.mkdir_p (Path.build path);
    Fiber.return ()
  | Pipe (outputs, l) -> exec_pipe ~ectx ~eenv outputs l
  | Diff diff ->
    (match ectx.mode with
     | Build -> Diff_action.exec ~sandbox:ectx.sandbox ~patch_back:None ectx.rule_loc diff
     | Shell_replay ->
       Diff_action.exec_without_promotion ~sandbox:ectx.sandbox ectx.rule_loc diff)
  | Extension (module A) ->
    let metadata =
      { ectx.metadata with can_run_in_action_runner = A.Spec.can_run_in_action_runner }
    in
    A.Spec.action A.v ~ectx:{ ectx with metadata } ~eenv

and redirect_out t ~ectx ~eenv ~perm outputs fn =
  redirect t ~ectx ~eenv ~out:(outputs, fn, perm) ()

and redirect_in t ~ectx ~eenv inputs fn = redirect t ~ectx ~eenv ~in_:(inputs, fn) ()

and redirect t ~ectx ~eenv ?in_ ?out () =
  let stdin_from, release_in =
    match in_ with
    | None -> eenv.stdin_from, ignore
    | Some (Stdin, fn) ->
      let in_ = Process.Io.file fn Process.Io.In in
      in_, fun () -> Process.Io.release in_
  in
  let stdout_to, stderr_to, release_out =
    match out with
    | None -> eenv.stdout_to, eenv.stderr_to, ignore
    | Some (outputs, fn, perm) ->
      let out = Process.Io.file fn Process.Io.Out ~perm:(File_perm.to_unix_perm perm) in
      let stdout_to, stderr_to =
        match outputs with
        | Stdout -> out, eenv.stderr_to
        | Stderr -> eenv.stdout_to, out
        | Outputs -> out, out
      in
      stdout_to, stderr_to, fun () -> Process.Io.release out
  in
  let+ () = exec t ~ectx ~eenv:{ eenv with stdin_from; stdout_to; stderr_to } in
  release_in ();
  release_out ()

and exec_list ts ~ectx ~eenv : unit Fiber.t =
  match ts with
  | [] -> Fiber.return ()
  | [ t ] -> exec t ~ectx ~eenv
  | t :: rest ->
    let stdout_to = Process.Io.multi_use eenv.stdout_to in
    let stderr_to = Process.Io.multi_use eenv.stderr_to in
    let stdin_from = Process.Io.multi_use eenv.stdin_from in
    let* () = exec t ~ectx ~eenv:{ eenv with stdout_to; stderr_to; stdin_from } in
    exec_list rest ~ectx ~eenv

and exec_pipe outputs ts ~ectx ~eenv : unit Fiber.t =
  let tmp_file () =
    Dtemp.file ~prefix:"dune-pipe-action-" ~suffix:("." ^ Outputs.to_string outputs)
  in
  let rec loop ~in_ ts =
    match ts with
    | [] -> assert false
    | [ last_t ] ->
      let eenv =
        match outputs with
        | Stderr -> { eenv with stdout_to = Process.Io.multi_use eenv.stderr_to }
        | _ -> eenv
      in
      let+ () = redirect_in last_t ~ectx ~eenv Stdin in_ in
      Dtemp.destroy File in_
    | t :: ts ->
      let out = tmp_file () in
      let eenv = { eenv with stderr_to = Process.Io.multi_use eenv.stderr_to } in
      let* () = redirect t ~ectx ~eenv ~in_:(Stdin, in_) ~out:(Stdout, out, Normal) () in
      Dtemp.destroy File in_;
      loop ~in_:out ts
  in
  match ts with
  | [] -> assert false
  | t1 :: ts ->
    let out = tmp_file () in
    let eenv =
      match outputs with
      | Outputs -> eenv
      | Stdout -> { eenv with stderr_to = Process.Io.multi_use eenv.stderr_to }
      | Stderr -> { eenv with stdout_to = Process.Io.multi_use eenv.stdout_to }
    in
    let* () = redirect_out t1 ~ectx ~eenv ~perm:Normal outputs out in
    loop ~in_:out ts
;;

type replay_input =
  { targets : Targets.Validated.t
  ; dir : Path.t
  ; env : Env.t
  ; rule_loc : Loc.t
  ; action : Action.t
  ; temp_dir : Path.t
  ; sandbox_policy_root : Path.t option
  }

let replay { targets; dir; env; rule_loc; action; temp_dir; sandbox_policy_root } =
  let () =
    match Action.find_extension_name action with
    | None -> ()
    | Some name ->
      Code_error.raise
        "action extension passed to dune shell replay"
        [ "extension", Dyn.string name ]
  in
  Dtemp.with_temp_dir_for_shell temp_dir ~f:(fun () ->
    let sandbox =
      Option.map sandbox_policy_root ~f:(fun root ->
        let base =
          Process.Sandbox.create_base ~action_trace_root:(Action_trace.root ())
        in
        Process.Sandbox.for_action base ~root)
    in
    Fiber.finalize
      ~finally:(fun () ->
        Option.iter sandbox ~f:Process.Sandbox.destroy;
        Fiber.return ())
      (fun () ->
         let build_deps (_ : Dep.Set.t) =
           Code_error.raise "dynamic dependencies in a static dune shell replay" []
         in
         let ectx =
           let metadata =
             Process_metadata.create
               ~purpose:(Process_metadata.Build_job (Some targets))
               ()
           in
           { root = dir; metadata; sandbox; rule_loc; build_deps; mode = Shell_replay }
         in
         let eenv =
           { working_dir = dir
           ; env
           ; stdout_to = Process.Io.inherit_stdout
           ; stderr_to = Process.Io.inherit_stderr
           ; stdin_from = Process.Io.null In
           ; exit_codes = Predicate.create (Int.equal 0)
           }
         in
         let open Fiber.O in
         Action.chdirs action
         |> Path.Build.Set.iter ~f:(fun path -> Path.mkdir_p (Path.build path));
         Fiber.collect_errors (fun () -> exec action ~ectx ~eenv)
         >>= function
         | Ok _ -> Fiber.return 0
         | Error errors ->
           let statuses, errors =
             List.partition_map errors ~f:(fun ({ Exn_with_backtrace.exn; _ } as error) ->
               match exn with
               | Shell_replay_failed status -> Left status
               | _ -> Right error)
           in
           (match statuses with
            | [] -> Fiber.reraise_all errors
            | status :: _ ->
              List.iter errors ~f:Dune_util.Report_error.report;
              Fiber.return (Process.Failure_mode.exit_code_of_raw_status status))))
;;

type input =
  { targets : Targets.Validated.t option (* Some Jane Street actions use [None] *)
  ; root : Path.t
  ; env : Env.t
  ; rule_loc : Loc.t
  ; execution_parameters : Execution_parameters.t
  ; sandbox : Process.Sandbox.t option
  ; action : Action.t
  ; job_slots : Action.t option
  }

(* The command runs with one job slot, before the action reserves its own job
   slots. Its standard output goes to a temporary file, like the stages of a
   pipe. *)
let eval_job_slots job_slots ~ectx ~(eenv : env) =
  match job_slots with
  | None -> Fiber.return 1
  | Some t ->
    let jobs = !Clflags.concurrency in
    let eenv =
      { eenv with
        env =
          Env.add
            eenv.env
            ~var:(Env.Var.of_string "DUNE_JOBS")
            ~value:(Int.to_string jobs)
      }
    in
    let out = Dtemp.file ~prefix:"dune-job-slots-" ~suffix:".stdout" in
    let+ () = redirect_out t ~ectx ~eenv ~perm:Normal Stdout out in
    let stdout = String.trim (Io.read_file_exn out) in
    Dtemp.destroy File out;
    (match Int.of_string stdout with
     | Some n when n > 0 -> min n jobs
     | Some _ | None ->
       User_error.raise
         ~loc:ectx.rule_loc
         [ Pp.textf
             "The job_slots command must print a positive integer, but it printed %S."
             stdout
         ])
;;

let prepare_base_env ~root ~env execution_parameters =
  let env =
    match
      Execution_parameters.workspace_root_to_build_path_prefix_map execution_parameters
    with
    | Unset -> env
    | Set target ->
      Dune_util.Build_path_prefix_map.extend_build_path_prefix_map
        env
        `New_rules_have_precedence
        (* TODO generify *)
        [ Some { source = Path.to_absolute_filename root; target } ]
  in
  let var = Env.Var.of_string "DUNE_PROJECT_ROOT" in
  match Execution_parameters.action_project_root execution_parameters with
  | None -> Env.remove env ~var
  | Some project_root ->
    (match Path.as_in_build_dir root with
     | None -> env
     | Some root ->
       let project_root = Path.Build.append_source root project_root in
       Env.add env ~var ~value:(Path.to_absolute_filename (Path.build project_root)))
;;

let prepare
      { targets
      ; root
      ; env
      ; rule_loc
      ; execution_parameters
      ; sandbox
      ; action = _
      ; job_slots
      }
      ~build_deps
  =
  let ectx =
    let metadata =
      Process_metadata.create ~purpose:(Process_metadata.Build_job targets) ()
    in
    { root; metadata; sandbox; rule_loc; build_deps; mode = Build }
  and eenv =
    let env = prepare_base_env ~root ~env execution_parameters in
    { working_dir = Path.root
    ; env
    ; stdout_to =
        Process.Io.make_stdout
          ~output_on_success:
            (Execution_parameters.action_stdout_on_success execution_parameters)
          ~output_limit:(Execution_parameters.action_stdout_limit execution_parameters)
    ; stderr_to =
        Process.Io.make_stderr
          ~output_on_success:
            (Execution_parameters.action_stderr_on_success execution_parameters)
          ~output_limit:(Execution_parameters.action_stderr_limit execution_parameters)
    ; stdin_from = Process.Io.null In
    ; exit_codes = Predicate.create (Int.equal 0)
    }
  in
  let* job_slots = eval_job_slots job_slots ~ectx ~eenv in
  let ectx = { ectx with metadata = { ectx.metadata with job_slots } } in
  let eenv =
    { eenv with
      env =
        Env.add
          eenv.env
          ~var:(Env.Var.of_string "DUNE_JOB_SLOTS")
          ~value:(Int.to_string job_slots)
    }
  in
  Fiber.return (ectx, eenv)
;;

let prepare_env input ~build_deps =
  let+ _, eenv = prepare input ~build_deps in
  eenv.env
;;

let exec ({ action; _ } as input) ~build_deps =
  let dynamic_deps_stages = ref [] in
  let build_deps deps =
    let+ facts = build_deps deps in
    dynamic_deps_stages := (deps, facts) :: !dynamic_deps_stages
  in
  Fiber.collect_errors (fun () ->
    let* ectx, eenv = prepare input ~build_deps in
    exec action ~ectx ~eenv)
  >>| function
  | Ok () -> Ok { Exec_result.dynamic_deps_stages = List.rev !dynamic_deps_stages }
  | Error exns -> Error exns
;;
