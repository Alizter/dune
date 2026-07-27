(* Tests for tracking Memo node events. *)

open! Stdune
open! Memo.O
open Test_helpers.Make ()

let tracked name f =
  Memo.create name ~input:(module Unit) ~on_event:(fun () _event -> ()) f
;;

let print_counts name evaluation =
  let counts = Memo.Evaluation.counts evaluation in
  printf "%s: live=%d validated=%d\n" name counts.live counts.validated
;;

let%expect_test "evaluation counts update while a node is running" =
  let started = Fiber.Ivar.create () in
  let continue = Fiber.Ivar.create () in
  let node =
    tracked "node" (fun () ->
      Memo.of_reproducible_fiber
        (let open Fiber.O in
         let* () = Fiber.Ivar.fill started () in
         Fiber.Ivar.read continue))
  in
  let evaluation = Memo.Evaluation.create () in
  Scheduler.run
    (Memo.run
       (Memo.fork_and_join
          (fun () -> Memo.Evaluation.observe evaluation (Memo.exec node ()))
          (fun () ->
             Memo.of_reproducible_fiber
               (let open Fiber.O in
                let* () = Fiber.Ivar.read started in
                print_counts "running" evaluation;
                Fiber.Ivar.fill continue ()))))
  |> ignore;
  print_counts "finished" evaluation;
  [%expect
    {|
    running: live=1 validated=0
    finished: live=1 validated=1
    |}]
;;

let%expect_test "an evaluation can only be observed once" =
  let evaluation = Memo.Evaluation.create () in
  run (Memo.Evaluation.observe evaluation (Memo.return ()));
  (try
     run (Memo.Evaluation.observe evaluation (Memo.return ()));
     print_endline "second observation accepted"
   with
   | Code_error.E _ -> print_endline "second observation rejected");
  [%expect {| second observation rejected |}]
;;

let%expect_test "evaluations count shared nodes independently" =
  let first_dependency_started = Fiber.Ivar.create () in
  let finish_first_dependency = Fiber.Ivar.create () in
  let later_dependency_started = Fiber.Ivar.create () in
  let finish_later_dependency = Fiber.Ivar.create () in
  let start_right = Fiber.Ivar.create () in
  let right_started = Fiber.Ivar.create () in
  let first_dependency =
    tracked "first-dependency" (fun () ->
      Memo.of_reproducible_fiber
        (let open Fiber.O in
         let* () = Fiber.Ivar.fill first_dependency_started () in
         Fiber.Ivar.read finish_first_dependency))
  in
  let later_dependency =
    tracked "later-dependency" (fun () ->
      Memo.of_reproducible_fiber
        (let open Fiber.O in
         let* () = Fiber.Ivar.fill later_dependency_started () in
         Fiber.Ivar.read finish_later_dependency))
  in
  let shared =
    tracked "shared" (fun () ->
      let* () = Memo.exec first_dependency () in
      Memo.exec later_dependency ())
  in
  let left = tracked "left" (fun () -> Memo.exec shared ()) in
  let right =
    tracked "right" (fun () ->
      let* () =
        Memo.of_reproducible_fiber
          (let open Fiber.O in
           let* () = Fiber.Ivar.fill right_started () in
           Fiber.Ivar.read start_right)
      in
      Memo.exec shared ())
  in
  let left_evaluation = Memo.Evaluation.create () in
  let right_evaluation = Memo.Evaluation.create () in
  Scheduler.run
    (Memo.run
       (Memo.fork_and_join
          (fun () ->
             Memo.fork_and_join
               (fun () -> Memo.Evaluation.observe left_evaluation (Memo.exec left ()))
               (fun () -> Memo.Evaluation.observe right_evaluation (Memo.exec right ())))
          (fun () ->
             Memo.of_reproducible_fiber
               (let open Fiber.O in
                let* () = Fiber.Ivar.read first_dependency_started in
                let* () = Fiber.Ivar.read right_started in
                let* () = Fiber.Ivar.fill start_right () in
                let* () = Scheduler.yield () in
                print_counts "left with existing dependency" left_evaluation;
                print_counts "right with existing dependency" right_evaluation;
                let* () = Fiber.Ivar.fill finish_first_dependency () in
                let* () = Fiber.Ivar.read later_dependency_started in
                print_counts "left with later dependency" left_evaluation;
                print_counts "right with later dependency" right_evaluation;
                Fiber.Ivar.fill finish_later_dependency ()))))
  |> ignore;
  print_counts "left finished" left_evaluation;
  print_counts "right finished" right_evaluation;
  [%expect
    {|
    left with existing dependency: live=3 validated=0
    right with existing dependency: live=3 validated=0
    left with later dependency: live=4 validated=1
    right with later dependency: live=4 validated=1
    left finished: live=4 validated=4
    right finished: live=4 validated=4
    |}]
;;

let%expect_test "an evaluation replays a dependency graph cached in the current run" =
  let leaf = tracked "leaf" (fun () -> Memo.return ()) in
  let untracked =
    Memo.create "untracked" ~input:(module Unit) (fun () -> Memo.exec leaf ())
  in
  let root = tracked "root" (fun () -> Memo.exec untracked ()) in
  let evaluate name =
    let evaluation = Memo.Evaluation.create () in
    run (Memo.Evaluation.observe evaluation (Memo.exec root ()));
    print_counts name evaluation
  in
  evaluate "first";
  evaluate "cached";
  Memo.reset Memo.Invalidation.empty;
  evaluate "restored";
  [%expect
    {|
    first: live=2 validated=2
    cached: live=2 validated=2
    restored: live=2 validated=2
    |}]
;;

let%expect_test "a node containing an error is still validated" =
  let failing = tracked "failing" (fun () -> failwith "failure") in
  let evaluation = Memo.Evaluation.create () in
  let result =
    Scheduler.run
      (run_collect_errors (fun () ->
         Memo.Evaluation.observe evaluation (Memo.exec failing ())))
  in
  (match result with
   | Ok () -> Code_error.raise "expected the evaluation to fail" []
   | Error _ -> ());
  print_counts "failed" evaluation;
  [%expect {| failed: live=1 validated=1 |}]
;;

let%expect_test _ =
  let divisor = Memo.Var.create ~name:"divisor" 2 in
  let table =
    Memo.create_rec
      "division via subtraction"
      ~input:(module Int)
      ~cutoff:Int.equal
      ~on_event:(fun input event ->
        let event =
          match (event : Memo.Event.t) with
          | Live -> "Live"
          | Validated -> "Validated"
        in
        printf "[on_event %d %s] called\n" input event)
      (fun f input ->
         let* divisor = Memo.Var.read divisor in
         if divisor < 0 then failwith "Negative divisors are not allowed!";
         if input < divisor
         then Memo.return 0
         else if input = divisor
         then Memo.return 1
         else
           let+ result = f (input - divisor) in
           result + 1)
  in
  List.iter [ 4; 5; 6; 4; 5; 6 ] ~f:(evaluate_and_print table);
  (* Nodes {1..6} become live; [Live] then [Validated] fire once for each live node. *)
  [%expect
    {|
    [on_event 4 Live] called
    [on_event 2 Live] called
    [on_event 2 Validated] called
    [on_event 4 Validated] called
    f 4 = Ok 2
    [on_event 5 Live] called
    [on_event 3 Live] called
    [on_event 1 Live] called
    [on_event 1 Validated] called
    [on_event 3 Validated] called
    [on_event 5 Validated] called
    f 5 = Ok 2
    [on_event 6 Live] called
    [on_event 6 Validated] called
    f 6 = Ok 3
    f 4 = Ok 2
    f 5 = Ok 2
    f 6 = Ok 3
    |}];
  Memo.reset (Memo.Var.set divisor 3);
  List.iter [ 3; 6; 9 ] ~f:(evaluate_and_print table);
  [%expect
    {|
    [on_event 3 Live] called
    [on_event 3 Validated] called
    f 3 = Ok 1
    [on_event 6 Live] called
    [on_event 6 Validated] called
    f 6 = Ok 2
    [on_event 9 Live] called
    [on_event 9 Validated] called
    f 9 = Ok 3
    |}];
  Memo.reset (Memo.Var.set divisor (-5));
  List.iter [ 8; 9; 9 ] ~f:(evaluate_and_print table);
  (* Liveness tracking works for nodes whose outputs are errors. *)
  [%expect
    {|
    [on_event 8 Live] called
    [on_event 8 Validated] called
    f 8 = Error
            [ { exn = "Failure(\"Negative divisors are not allowed!\")"
              ; backtrace = ""
              }
            ]
    [on_event 9 Live] called
    [on_event 9 Validated] called
    f 9 = Error
            [ { exn = "Failure(\"Negative divisors are not allowed!\")"
              ; backtrace = ""
              }
            ]
    f 9 = Error
            [ { exn = "Failure(\"Negative divisors are not allowed!\")"
              ; backtrace = ""
              }
            ]
    |}];
  Memo.reset (Memo.Var.set divisor 0);
  List.iter [ 9; 10; 9 ] ~f:(evaluate_and_print table);
  (* Liveness tracking works with dependency cycles too. *)
  [%expect
    {|
    [on_event 9 Live] called
    [on_event 9 Validated] called
    Dependency cycle detected:
    - ("division via subtraction", 9)
    f 9 = Error
            [ { exn = "Cycle_error.E [ (\"division via subtraction\", 9) ]"
              ; backtrace = ""
              }
            ]
    [on_event 10 Live] called
    [on_event 10 Validated] called
    Dependency cycle detected:
    - ("division via subtraction", 10)
    f 10 = Error
             [ { exn = "Cycle_error.E [ (\"division via subtraction\", 10) ]"
               ; backtrace = ""
               }
             ]
    Dependency cycle detected:
    - ("division via subtraction", 9)
    f 9 = Error
            [ { exn = "Cycle_error.E [ (\"division via subtraction\", 9) ]"
              ; backtrace = ""
              }
            ]
    |}]
;;
