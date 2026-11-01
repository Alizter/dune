open Stdune
open Dune_engine
open Dune_scheduler

let go =
  let config =
    Clflags.display := Short;
    { Scheduler.Config.concurrency = 1
    ; print_ctrl_c_warning = true
    ; watch_exclusions = []
    }
  in
  fun f -> Scheduler.Run.go config ~file_watcher:No_watcher f
;;

let true_ = Bin.which "true" ~path:(Env_path.path Env.initial) |> Option.value_exn

let dtemp_dir purpose =
  let env = Dune_engine.For_tests.Dtemp.add_to_env Env.empty ~purpose in
  Env.get env Env.Var.temp_dir |> Option.value_exn |> Path.of_string
;;

let%expect_test "action and Dune temporary directories" =
  let dune_dir = dtemp_dir Internal_job in
  let action_dir = dtemp_dir (Build_job None) in
  let dune_file = Dune_engine.For_tests.Dtemp.file ~prefix:"dune" ~suffix:"file" in
  let action_file = Path.relative action_dir "action-file" in
  Io.write_file_exn action_file "";
  let exists path = Fpath.exists (Path.to_string path) in
  Printf.printf "same directory: %b\n" (Path.equal dune_dir action_dir);
  Printf.printf
    "Dune file uses Dune directory: %b\n"
    (Path.equal dune_dir (Path.parent_exn dune_file));
  Printf.printf "files before clear: %b %b\n" (exists dune_file) (exists action_file);
  Dune_engine.For_tests.Dtemp.clear ();
  Printf.printf "files after clear: %b %b\n" (exists dune_file) (exists action_file);
  [%expect
    {|
    same directory: false
    Dune file uses Dune directory: true
    files before clear: true true
    files after clear: false false
    |}]
;;

let sh = lazy (Bin.which "sh" ~path:(Env_path.path Env.initial) |> Option.value_exn)

let%expect_test "returned and accepted numeric exits" =
  let sh = Lazy.force sh in
  let (), code = go (fun () -> Process.run ~display:Quiet Return sh [ "-c"; "exit 7" ]) in
  Printf.printf "returned: %d\n" code;
  let accepted =
    go (fun () ->
      Process.run
        ~display:Quiet
        (Accept (Predicate.create (Int.equal 7)))
        sh
        [ "-c"; "exit 7" ])
  in
  (match accepted with
   | Ok () -> print_endline "accepted: zero"
   | Error code -> Printf.printf "accepted: %d\n" code);
  let output, code =
    go (fun () ->
      Process.run_capture ~display:Quiet Return sh [ "-c"; "printf captured; exit 7" ])
  in
  Printf.printf "captured: %S, exit: %d\n" output code;
  [%expect
    {|
    returned: 7
    accepted: 7
    captured: "captured", exit: 7
    |}]
;;

let%expect_test "unreported inherited process statuses" =
  List.iter [ "exit 0"; "exit 7"; "kill -TERM $$" ] ~f:(fun script ->
    let status =
      go (fun () ->
        Process.run_inherit_std_in_out_unreported
          ~dir:Path.root
          ~env:Env.initial
          ~metadata:Process_metadata.default
          (Lazy.force sh)
          [ "-c"; script ])
    in
    match status with
    | Unix.WEXITED code -> Printf.printf "exited: %d\n" code
    | WSIGNALED signal ->
      Printf.printf "signaled: %s\n" (Signal.name (Signal.of_int signal))
    | WSTOPPED signal ->
      Printf.printf "stopped: %s\n" (Signal.name (Signal.of_int signal)));
  [%expect
    {|
    exited: 0
    exited: 7
    signaled: TERM
    |}]
;;

let%expect_test "unreported execution preserves build cancellation" =
  let cancellation = Fiber.Cancel.create () in
  let build =
    Process.Build.create ~action_runner:None ~run_id:Run_id.Batch ~cancellation
  in
  let result =
    go (fun () ->
      let open Fiber.O in
      let* () = Fiber.Cancel.fire cancellation in
      Fiber.collect_errors (fun () ->
        Process.Build.with_ build (fun () ->
          Process.run_inherit_std_in_out_unreported
            ~dir:Path.root
            ~env:Env.initial
            ~metadata:Process_metadata.default
            true_
            [])))
  in
  let cancelled =
    match result with
    | Ok _ -> false
    | Error errors ->
      List.exists errors ~f:(fun { Exn_with_backtrace.exn; _ } ->
        match exn with
        | Memo.Non_reproducible Scheduler.Run.Build_cancelled -> true
        | _ -> false)
  in
  Printf.printf "cancelled: %b\n" cancelled;
  [%expect {| cancelled: true |}]
;;

let%expect_test "process timeout" =
  let result =
    go (fun () ->
      Process.run
        ~display:Quiet
        (Timeout { timeout = Some (Time.Span.of_secs 0.01); failure_mode = Return })
        (Lazy.force sh)
        [ "-c"; "sleep 2" ])
  in
  (match result with
   | Error `Timed_out -> print_endline "timed out"
   | Ok (_, code) -> Printf.printf "finished: %d\n" code);
  [%expect {| timed out |}]
;;

let%expect_test "null input" =
  let stdin_from = Process.(Io.null In) in
  let run () = Process.run ~display:Quiet ~stdin_from Strict true_ [] in
  let _res = go run in
  [%expect {||}]
;;

let%expect_test "null output" =
  let stdout_to = Process.(Io.null Out) in
  let stderr_to = Process.(Io.null Out) in
  let run () = Process.run ~display:Quiet ~stdout_to ~stderr_to Strict true_ [] in
  let _res = go run in
  [%expect {||}]
;;
