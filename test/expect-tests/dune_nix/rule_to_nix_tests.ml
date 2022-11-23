(* open Stdune *)
(* open Dune_engine *)
(* open Dune_nix *)

let%expect_test _ = assert false
  [@@expect.uncaught_exn
    {|
  (* CR expect_test_collector: This test expectation appears to contain a backtrace.
     This is strongly discouraged as backtraces are fragile.
     Please change this test to not include a backtrace. *)

  "Assert_failure test/expect-tests/dune_nix/rule_to_nix_tests.ml:5:20"
  Raised at Dune_nix_tests__Rule_to_nix_tests.(fun) in file "test/expect-tests/dune_nix/rule_to_nix_tests.ml", line 5, characters 20-32
  Called from Expect_test_collector.Make.Instance_io.exec in file "collector/expect_test_collector.ml", line 262, characters 12-19 |}]
