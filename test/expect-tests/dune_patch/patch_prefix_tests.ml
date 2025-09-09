open Stdune

(* Testing patch prefix parsing *)

let test p =
  Dune_patch.For_tests.prefix_of_patch ~loc:Loc.none p |> Printf.printf "prefix: %d"
;;

let%expect_test "prefix_of_patch - basic" =
  (* "--- a/foo.ml", "+++ b/foo.ml" *)
  test Patch_examples.basic;
  [%expect {| prefix: 1 |}]
;;

let%expect_test "prefix_of_patch - subdirectory" =
  (* "--- a/dir/foo.ml", "+++ b/dir/foo.ml" *)
  test Patch_examples.subdirectory;
  [%expect {| prefix: 1 |}]
;;

let%expect_test "prefix_of_patch - combined" =
  (* Combined basic + subdirectory *)
  test Patch_examples.combined;
  [%expect {| prefix: 1 |}]
;;

let%expect_test "prefix_of_patch - new file" =
  (* "--- /dev/null", "+++ b/foo.ml" *)
  test Patch_examples.new_file;
  [%expect {| prefix: 1 |}]
;;

let%expect_test "prefix_of_patch - delete file" =
  (* "--- a/foo.ml", "+++ /dev/null" *)
  test Patch_examples.delete_file;
  [%expect {| prefix: 1 |}]
;;

let%expect_test "prefix_of_patch - unified format" =
  (* "--- a/foo.ml", "+++ b/foo.ml" (unified format) *)
  test Patch_examples.unified;
  [%expect {| prefix: 1 |}]
;;

let%expect_test "prefix_of_patch - no prefix" =
  (* "--- foo.ml", "+++ foo.ml" (no prefix) *)
  test Patch_examples.no_prefix;
  [%expect {| prefix: 0 |}]
;;

let%expect_test "prefix_of_patch - custom prefix" =
  (* "--- bar/foo.ml", "+++ baz/foo.ml" (custom prefix) *)
  test Patch_examples.random_prefix;
  [%expect {| prefix: 1 |}]
;;

let%expect_test "prefix_of_patch - spaces" =
  (* "--- a/foo bar", "+++ b/foo bar" (spaces in filename) *)
  test Patch_examples.spaces;
  [%expect {| prefix: 1 |}]
;;

let%expect_test "prefix_of_patch - unified spaces" =
  (* "--- \"a/foo bar\"", "+++ \"b/foo bar\"" (quoted spaces) *)
  test Patch_examples.unified_spaces;
  [%expect {| prefix: 1 |}]
;;

let%expect_test "prefix_of_patch - hello world" =
  (* "--- /dev/null", "+++ b/foo.ml" *)
  test Patch_examples.hello_world;
  [%expect {| prefix: 1 |}]
;;

let%expect_test "prefix_of_patch - rename patch" =
  (* No --- or +++ lines, just rename directives *)
  test Patch_examples.rename_patch;
  [%expect {| prefix: 0 |}]
;;

let%expect_test "prefix_of_patch - git ext delete" =
  (* "--- a/foo.ml", "+++ /dev/null" *)
  test Patch_examples.git_ext_delete_only;
  [%expect {| prefix: 1 |}]
;;

let%expect_test "prefix_of_patch - git ext create" =
  (* "--- /dev/null", "+++ b/foo.ml" *)
  test Patch_examples.git_ext_create_only;
  [%expect {| prefix: 1 |}]
;;

let%expect_test "prefix_of_patch - edit with rename" =
  (* "--- a/source.ml", "+++ b/target.ml" *)
  test Patch_examples.edit_with_rename;
  [%expect {| prefix: 1 |}]
;;
