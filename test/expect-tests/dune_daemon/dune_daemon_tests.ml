open Stdune
open Fiber.O
include Dune_scheduler

let () =
  Path.set_root (Path.External.of_filename_relative_to_initial_cwd ".");
  Path.Build.set_build_dir (Path.Outside_build_dir.of_string "_build")
;;

let config =
  Dune_engine.Clflags.display := Quiet;
  { Scheduler.Config.concurrency = 1
  ; print_ctrl_c_warning = false
  ; watch_exclusions = []
  }
;;

let files = List.iter ~f:(fun (f, contents) -> Io.String_path.write_file f contents)
let default_files = [ "dune-project", "(lang dune 3.21)" ]

let run ?(setup = default_files) f =
  let cwd = Sys.getcwd () in
  let dir = Temp.create Dir ~prefix:"dune" ~suffix:"daemon_test" in
  let run () =
    Fiber.with_error_handler
      (fun () ->
         files setup;
         f ())
      ~on_error:(fun exn ->
        Exn_with_backtrace.pp_uncaught Format.err_formatter exn;
        Format.pp_print_flush Format.err_formatter ();
        Exn_with_backtrace.reraise exn)
  in
  Exn.protect
    ~finally:(fun () -> Sys.chdir cwd)
    ~f:(fun () ->
      Sys.chdir (Path.to_string dir);
      Scheduler.Run.go config run ~timeout:(Time.Span.of_secs 5.0) ~on_event:(fun _ _ ->
        ()))
;;

let dune_prog =
  lazy
    (let path = Env_path.path Env.initial in
     Bin.which ~path "dune" |> Option.value_exn |> Path.to_absolute_filename)
;;

let run_server ~root_dir =
  let stdout_i, stdout_w = Unix.pipe ~cloexec:true () in
  let stderr_i, stderr_w = Unix.pipe ~cloexec:true () in
  let prog = Lazy.force dune_prog in
  let argv = [ prog; "build"; "--root"; root_dir; "--passive-watch-mode" ] in
  let pid = Spawn.spawn ~prog ~argv ~stdout:stdout_w ~stderr:stderr_w () |> Pid.of_int in
  Unix.close stdout_w;
  Unix.close stderr_w;
  Unix.close stdout_i;
  Unix.close stderr_i;
  pid
;;

let with_daemon f =
  let xdg_runtime_dir = Filename.get_temp_dir_name () in
  Unix.putenv "XDG_RUNTIME_DIR" xdg_runtime_dir;
  let pid = run_server ~root_dir:"." in
  Fiber.finalize
    (fun () ->
       (* Wait for daemon to be ready *)
       let rec wait_loop retries =
         if retries <= 0
         then Fiber.return (Error "Daemon failed to start")
         else
           let* running = Dune_daemon.ping () in
           if running
           then Fiber.return (Ok ())
           else
             let* () = Scheduler.sleep (Time.Span.of_secs 0.2) in
             wait_loop (retries - 1)
       in
       let* ready = wait_loop 25 in
       match ready with
       | Error msg ->
         print_endline msg;
         Fiber.return ()
       | Ok () -> f pid)
    ~finally:(fun () ->
      Unix.kill (Pid.to_int pid) Sys.sigterm;
      Fiber.return ())
;;

let%expect_test "ping returns false when no daemon is running" =
  run (fun () ->
    let+ result = Dune_daemon.ping () in
    print_endline (Bool.to_string result));
  [%expect {| false |}]
;;

let%expect_test "ping returns true after daemon is spawned" =
  run (fun () ->
    with_daemon (fun _pid ->
      let+ result = Dune_daemon.ping () in
      print_endline (Bool.to_string result)));
  [%expect {| true |}]
;;

let%expect_test "ping returns false when socket exists but not responding" =
  run (fun () ->
    (* Create the socket directory and a socket file that nothing listens on *)
    Unix.mkdir "_build" 0o755;
    Unix.mkdir "_build/.rpc" 0o755;
    let socket_path = "_build/.rpc/dune" in
    let sock = Unix.socket ~cloexec:true Unix.PF_UNIX Unix.SOCK_STREAM 0 in
    Unix.bind sock (Unix.ADDR_UNIX socket_path);
    (* Don't call listen - socket exists but won't accept connections *)
    Unix.close sock;
    let+ result = Dune_daemon.ping () in
    print_endline (Bool.to_string result));
  [%expect {| false |}]
;;
