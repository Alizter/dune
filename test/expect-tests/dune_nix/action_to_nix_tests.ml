open Stdune
open Dune_engine
open Dune_nix

let pr = Format.printf "%a" (fun fmt x -> Pp.to_fmt fmt (Dune_nix.Ast.pp x))

let nix_eval nix =
  ignore
    (Sys.command
       (Format.asprintf "nix eval --impure --show-trace --expr '%a'"
          (fun fmt x -> Pp.to_fmt fmt (Dune_nix.Ast.pp x))
          nix))

let nix_build nix =
  ignore
    (Sys.command
       (Format.asprintf "nix build --impure --show-trace --expr '%a'"
          (fun fmt x -> Pp.to_fmt fmt (Dune_nix.Ast.pp x))
          nix))

let%expect_test "hello world" =
  (* Hack to set build directory as "$out" *)
  let () =
    Path.Build.set_build_dir
      (Path.Outside_build_dir.External (Path.External.Expert.of_string "$out"))
  in
  let path = Path.Build.of_string "hello_world" in
  let action = Action.(progn [ write_file path {|"Hello World!"|} ]) in
  let nix =
    Action_to_nix.translate ~expanded_deps:Path.Set.empty
      ~file_targets:(Path.Build.Set.of_list [ path ])
      ~dir_targets:Path.Build.Set.empty action
  in
  pr nix;
  [%expect.unreachable];
  nix_build nix;
  [%expect.unreachable];
  (* ls *)
  ignore (Sys.command "ls result; cat result/hello_world");
  [%expect.unreachable]
  [@@expect.uncaught_exn
    {|
  (* CR expect_test_collector: This test expectation appears to contain a backtrace.
     This is strongly discouraged as backtraces are fragile.
     Please change this test to not include a backtrace. *)

  ( "(\"Fdecl.set: already set\",\
   \n{ old = External \"$out\"; new_ = External \"hello_world\" })")
  Raised at Stdune__Code_error.raise in file "otherlibs/stdune/src/code_error.ml", line 11, characters 30-62
  Called from Stdune__Path.Build.set_build_dir in file "otherlibs/stdune/src/path.ml", line 712, characters 4-37
  Called from Dune_nix__Action_to_nix.translate.(fun) in file "src/dune_nix/action_to_nix.ml", line 31, characters 8-155
  Called from Stdlib__List.rev_map.rmap_f in file "list.ml", line 103, characters 22-25
  Called from Stdune__List.map in file "otherlibs/stdune/src/list.ml", line 5, characters 19-33
  Called from Dune_nix__Action_to_nix.translate in file "src/dune_nix/action_to_nix.ml", line 30, characters 4-222
  Called from Dune_nix_tests__Action_to_nix_tests.(fun) in file "test/expect-tests/dune_nix/action_to_nix_tests.ml", line 30, characters 4-158
  Called from Expect_test_collector.Make.Instance_io.exec in file "collector/expect_test_collector.ml", line 262, characters 12-19 |}]
