open Stdune
open Dune_tests_common
module Action_builder = Dune_engine.Action_builder
module Build_system = Dune_engine.Build_system
module Request = Build_system.Request

let () = init ()
let () = Path.mkdir_p Path.build_dir

let scheduler_config =
  { Dune_scheduler.Scheduler.Config.concurrency = 1
  ; print_ctrl_c_warning = false
  ; watch_exclusions = []
  }
;;

let run fiber =
  Dune_scheduler.Scheduler.Run.go
    scheduler_config
    ~timeout:(Time.Span.of_secs 1.)
    ~file_watcher:No_watcher
    (fun () -> fiber)
;;

let tracked name f =
  Memo.create name ~input:(module Unit) ~on_event:(fun () _event -> ()) f
;;

let print_stats label goal =
  let { Request.Stats.number_of_rules_discovered; number_of_rules_validated } =
    Request.Goal.stats goal
  in
  Printf.printf
    "%s: discovered=%d validated=%d\n"
    label
    number_of_rules_discovered
    number_of_rules_validated
;;

let run_request request =
  Build_system.run_build_requests ~build_started_at:(Time.now ()) request
;;

let run_goals goals = run_request (Request.create goals)
let run_goal goal = run_goals [ goal ]

let%expect_test "request stats are collected only when requested" =
  let root = tracked "untracked-request-stats-root" (fun () -> Memo.return ()) in
  let goal = Request.Goal.create (Action_builder.of_memo (Memo.exec root ())) in
  (match run (run_goal goal) with
   | Ok () -> print_endline "build succeeded"
   | Error `Already_reported -> print_endline "build failed");
  print_stats "untracked" goal;
  [%expect
    {|
    build succeeded
    untracked: discovered=0 validated=0
    |}]
;;

let%expect_test "request stats update during a build attempt" =
  let leaf_started = Fiber.Ivar.create () in
  let finish_leaf = Fiber.Ivar.create () in
  let leaf =
    tracked "request-stats-leaf" (fun () ->
      Memo.of_reproducible_fiber
        (let open Fiber.O in
         let* () = Fiber.Ivar.fill leaf_started () in
         Fiber.Ivar.read finish_leaf))
  in
  let root = tracked "request-stats-root" (fun () -> Memo.exec leaf ()) in
  let goal =
    Request.Goal.create_with_progress (Action_builder.of_memo (Memo.exec root ()))
  in
  print_stats "before" goal;
  let outcome, () =
    run
      (Fiber.fork_and_join
         (fun () -> run_goal goal)
         (fun () ->
            let open Fiber.O in
            let* () = Fiber.Ivar.read leaf_started in
            print_stats "running" goal;
            Fiber.Ivar.fill finish_leaf ()))
  in
  print_stats "finished" goal;
  (match outcome with
   | Ok () -> print_endline "build succeeded"
   | Error `Already_reported -> print_endline "build failed");
  [%expect
    {|
    before: discovered=0 validated=0
    running: discovered=2 validated=0
    finished: discovered=2 validated=2
    build succeeded
    |}]
;;

let%expect_test "goals in one build request have independent stats" =
  let left_started = Fiber.Ivar.create () in
  let finish_left = Fiber.Ivar.create () in
  let right_started = Fiber.Ivar.create () in
  let finish_right = Fiber.Ivar.create () in
  let left =
    tracked "request-stats-left" (fun () ->
      Memo.of_reproducible_fiber
        (let open Fiber.O in
         let* () = Fiber.Ivar.fill left_started () in
         Fiber.Ivar.read finish_left))
  in
  let right_leaf =
    tracked "request-stats-right-leaf" (fun () ->
      Memo.of_reproducible_fiber
        (let open Fiber.O in
         let* () = Fiber.Ivar.fill right_started () in
         Fiber.Ivar.read finish_right))
  in
  let right = tracked "request-stats-right" (fun () -> Memo.exec right_leaf ()) in
  let left_goal =
    Request.Goal.create_with_progress (Action_builder.of_memo (Memo.exec left ()))
  in
  let right_goal =
    Request.Goal.create_with_progress (Action_builder.of_memo (Memo.exec right ()))
  in
  let outcome, () =
    run
      (Fiber.fork_and_join
         (fun () -> run_goals [ left_goal; right_goal ])
         (fun () ->
            let open Fiber.O in
            let* () = Fiber.Ivar.read left_started
            and* () = Fiber.Ivar.read right_started in
            print_stats "left running" left_goal;
            print_stats "right running" right_goal;
            let* () = Fiber.Ivar.fill finish_left () in
            Fiber.Ivar.fill finish_right ()))
  in
  print_stats "left finished" left_goal;
  print_stats "right finished" right_goal;
  (match outcome with
   | Ok () -> print_endline "build succeeded"
   | Error `Already_reported -> print_endline "build failed");
  [%expect
    {|
    left running: discovered=1 validated=0
    right running: discovered=2 validated=0
    left finished: discovered=1 validated=1
    right finished: discovered=2 validated=2
    build succeeded
    |}]
;;

let%expect_test "tracked goals see work shared with an earlier untracked goal" =
  let leaf_started = Fiber.Ivar.create () in
  let finish_leaf = Fiber.Ivar.create () in
  let leaf =
    tracked "mixed-request-stats-leaf" (fun () ->
      Memo.of_reproducible_fiber
        (let open Fiber.O in
         let* () = Fiber.Ivar.fill leaf_started () in
         Fiber.Ivar.read finish_leaf))
  in
  let root = tracked "mixed-request-stats-root" (fun () -> Memo.exec leaf ()) in
  let build = Action_builder.of_memo (Memo.exec root ()) in
  let untracked_goal = Request.Goal.create build in
  let tracked_goal = Request.Goal.create_with_progress build in
  let outcome, () =
    run
      (Fiber.fork_and_join
         (fun () -> run_goals [ untracked_goal; tracked_goal ])
         (fun () ->
            let open Fiber.O in
            let* () = Fiber.Ivar.read leaf_started in
            print_stats "tracked running" tracked_goal;
            Fiber.Ivar.fill finish_leaf ()))
  in
  print_stats "tracked finished" tracked_goal;
  (match outcome with
   | Ok () -> print_endline "build succeeded"
   | Error `Already_reported -> print_endline "build failed");
  [%expect
    {|
    tracked running: discovered=2 validated=0
    tracked finished: discovered=2 validated=2
    build succeeded
    |}]
;;

let%expect_test "a retry replaces the previous attempt's stats" =
  let second_attempt = ref false in
  let second_attempt_started = Fiber.Ivar.create () in
  let continue_second_attempt = Fiber.Ivar.create () in
  let root = tracked "request-stats-retry-root" (fun () -> Memo.return ()) in
  let build =
    Memo.of_thunk (fun () ->
      let open Memo.O in
      let* () =
        if not !second_attempt
        then Memo.return ()
        else
          Memo.of_reproducible_fiber
            (let open Fiber.O in
             let* () = Fiber.Ivar.fill second_attempt_started () in
             Fiber.Ivar.read continue_second_attempt)
      in
      Memo.exec root ())
  in
  let goal = Request.Goal.create_with_progress (Action_builder.of_memo build) in
  let first_request = Request.create [ goal ] in
  Request.cancel_completion first_request;
  (match run (run_request first_request) with
   | Ok () -> ()
   | Error `Already_reported -> print_endline "first attempt failed");
  print_stats "first attempt" goal;
  Printf.printf "first attempt completed goal: %b\n" (Request.Goal.is_finished goal);
  second_attempt := true;
  let outcome, () =
    run
      (Fiber.fork_and_join
         (fun () -> run_goal goal)
         (fun () ->
            let open Fiber.O in
            let* () = Fiber.Ivar.read second_attempt_started in
            print_stats "retry before reaching root" goal;
            Fiber.Ivar.fill continue_second_attempt ()))
  in
  print_stats "retry finished" goal;
  (match outcome with
   | Ok () -> print_endline "retry succeeded"
   | Error `Already_reported -> print_endline "retry failed");
  [%expect
    {|
    first attempt: discovered=1 validated=1
    first attempt completed goal: false
    retry before reaching root: discovered=0 validated=0
    retry finished: discovered=1 validated=1
    retry succeeded
    |}]
;;
