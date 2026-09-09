open Import
open Fiber.O
module Rpc_common = Rpc.Rpc_common

type t =
  | Existing of
      { lock_held_by : Global_lock.Lock_held_by.t
      ; wait : bool
      }
  | Start

let prepare ~common ~config =
  let enabled =
    match Common.watch common with
    | No -> Dune_config.daemon_enabled config
    | Yes _ -> false
  in
  match Global_lock.lock () with
  | Error lock_held_by -> `Rpc (Existing { lock_held_by; wait = enabled })
  | Ok () ->
    if enabled
    then (
      if Common.action_runner_requested common
      then
        User_error.raise
          [ Pp.text
              "Cannot automatically start a daemon with action runner flags. Start a \
               watch server with those flags instead."
          ];
      Global_lock.unlock ();
      `Rpc Start)
    else `Local
;;

let log_file = Path.Build.relative Path.Build.root ".daemon.log"

let spawn () =
  let prog = Path.to_absolute_filename (Util.dune_executable ()) in
  let args =
    Array.Immutable.of_list
      [ "internal"
      ; "daemon"
      ; "--root"
      ; Path.to_absolute_filename Path.root
      ; "--build-dir"
      ; Path.to_absolute_filename Path.build_dir
      ]
  in
  let output =
    Unix.openfile
      (Path.Build.to_string log_file)
      [ O_WRONLY; O_CREAT; O_APPEND; O_CLOEXEC ]
      0o600
    |> Fd.unsafe_of_unix_file_descr
  in
  Exn.protect
    ~finally:(fun () -> Fd.close output)
    ~f:(fun () ->
      let pid =
        Spawn.spawn
          ~env:Env.initial
          ~prog
          ~argv0:prog
          ~args
          ~stdin:(Lazy.force Dev_null.in_)
          ~stdout:output
          ~stderr:output
          ~setpgid:Spawn.Pgid.new_process_group
          ~pdeathsig:(Signal.of_int 0)
          ()
      in
      Scheduler.preserve_child_process pid;
      pid)
;;

let child_is_running pid =
  match Proc.wait (Pid pid) [ WNOHANG ] with
  | Some _ -> false
  | None ->
    (* On Unix the scheduler may already have reaped this untracked child. *)
    Sys.win32 || Pid.check pid `Pid = `Alive
;;

let wait_for_connection ~child ~lock_held_by =
  let started = Option.is_some child in
  let rec loop child lock_held_by =
    let* connection = Rpc_common.establish_connection ~lock_held_by () in
    match connection with
    | Ok connection -> Fiber.return (connection, lock_held_by)
    | Error _ ->
      let child =
        match child with
        | Some pid when child_is_running pid -> child
        | Some _ | None -> None
      in
      let lock_held_by =
        match child with
        | Some _ -> lock_held_by
        | None ->
          (match Global_lock.lock () with
           | Error lock_held_by -> lock_held_by
           | Ok () ->
             Global_lock.unlock ();
             if started
             then
               User_error.raise
                 ~hints:
                   [ Pp.textf
                       "See %s for daemon output."
                       (Path.Build.to_string_maybe_quoted log_file)
                   ]
                 [ Pp.text "Dune daemon exited before becoming ready." ]
             else
               User_error.raise
                 [ Pp.text "RPC server stopped before accepting the request." ])
      in
      let* () = Scheduler.sleep (Time.Span.of_secs 0.2) in
      loop child lock_held_by
  in
  loop child lock_held_by
;;

let connect t =
  let* () = Fiber.return () in
  match t with
  | Existing { lock_held_by; wait = false } ->
    let+ connection = Rpc_common.establish_connection ~lock_held_by () in
    User_error.ok_exn connection, lock_held_by
  | Start | Existing { wait = true; _ } ->
    let section =
      Console.Status_line.add_section
        (Live (fun () -> Pp.text "Waiting for RPC server to start"))
    in
    Fiber.finalize
      (fun () ->
         let child, lock_held_by =
           match t with
           | Start -> Some (spawn ()), Global_lock.Lock_held_by.Unknown
           | Existing { lock_held_by; _ } -> None, lock_held_by
         in
         wait_for_connection ~child ~lock_held_by)
      ~finally:(fun () ->
        Console.Status_line.remove_section section;
        Fiber.return ())
;;

let command =
  let open Import in
  let term =
    let+ builder = Common.Builder.term in
    let builder = Common.Builder.for_daemon builder in
    let common, config = Common.init_build builder in
    match Global_lock.lock () with
    | Error _ -> ()
    | Ok () ->
      let build_loop = Common.build_loop common in
      Scheduler_setup.go_with_rpc_server_and_file_watcher ~common ~config (fun () ->
        Dune_engine.Build_loop.run build_loop (fun () ->
          Dune_engine.Build_loop.poll
            build_loop
            ~action_runner:(Common.action_runner common)
            ~sticky_goal:None))
  in
  Cmd.v (Cmd.info "daemon") term
;;
