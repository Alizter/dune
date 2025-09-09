open Stdune

(* Testing patch application *)

let test_apply_patches patches files check_files =
  let dir = Temp.create Dir ~prefix:"dune" ~suffix:"apply_test" in
  Sys.chdir (Path.to_string dir);
  List.iter files ~f:(fun (f, contents) ->
    let parent = Filename.dirname f in
    if parent <> "." then ignore (Fpath.mkdir_p parent);
    Io.String_path.write_file f contents);
  Dune_patch.For_tests.apply_patches ~dir patches;
  List.iter check_files ~f:(fun f ->
    let path = Path.of_string f in
    if Path.exists path
    then (
      let contents = Io.read_file path in
      Printf.printf "%s:\n%s" f contents)
    else Printf.printf "%s: NOT FOUND\n" f)
;;

let%expect_test "apply_patches - basic" =
  let patches = Dune_patch.For_tests.parse_patches ~loc:Loc.none Patch_examples.basic in
  test_apply_patches patches [ "foo.ml", "This is wrong\n" ] [ "foo.ml" ];
  [%expect
    {|
    foo.ml:
    This is right |}]
;;

let%expect_test "apply_patches - new_file" =
  let patches =
    Dune_patch.For_tests.parse_patches ~loc:Loc.none Patch_examples.new_file
  in
  test_apply_patches patches [] [ "foo.ml" ];
  [%expect
    {|
    foo.ml:
    This is right
    |}]
;;

let%expect_test "apply_patches - delete_file" =
  let patches =
    Dune_patch.For_tests.parse_patches ~loc:Loc.none Patch_examples.delete_file
  in
  test_apply_patches patches [ "foo.ml", "This is wrong\n" ] [ "foo.ml" ];
  [%expect {| foo.ml: NOT FOUND |}]
;;

let%expect_test "apply_patches - missing file for edit" =
  let patches = Dune_patch.For_tests.parse_patches ~loc:Loc.none Patch_examples.basic in
  test_apply_patches patches [] [ "foo.ml" ];
  [%expect.unreachable]
[@@expect.uncaught_exn
  {| ("Error: Cannot edit file \"foo.ml\": file does not exist\n") |}]
;;

let%expect_test "apply_patches - create over existing file" =
  let patches =
    Dune_patch.For_tests.parse_patches ~loc:Loc.none Patch_examples.new_file
  in
  test_apply_patches patches [ "foo.ml", "Old content\n" ] [ "foo.ml" ];
  [%expect
    {|
    foo.ml:
    This is right
    |}]
;;

let%expect_test "apply_patches - delete missing file" =
  let patches =
    Dune_patch.For_tests.parse_patches ~loc:Loc.none Patch_examples.delete_file
  in
  test_apply_patches patches [] [ "foo.ml" ];
  [%expect {| foo.ml: NOT FOUND |}]
;;

(* Edit with rename now works correctly after prefix parsing fix. *)
let%expect_test "apply_patches - edit_with_rename" =
  let patches =
    Dune_patch.For_tests.parse_patches ~loc:Loc.none Patch_examples.edit_with_rename
  in
  test_apply_patches patches [ "source.ml", "This is wrong\n" ] [ "target.ml" ];
  [%expect
    {|
    target.ml:
    This is right
    |}]
;;

let%expect_test "apply_patches - git_ext_delete_only (parses as Delete)" =
  let patches =
    Dune_patch.For_tests.parse_patches ~loc:Loc.none Patch_examples.git_ext_delete_only
  in
  test_apply_patches patches [ "foo.ml", "Hello World\n" ] [ "foo.ml" ];
  [%expect {| foo.ml: NOT FOUND |}]
;;

let%expect_test "apply_patches - git_ext_create_only (parses as Create)" =
  let patches =
    Dune_patch.For_tests.parse_patches ~loc:Loc.none Patch_examples.git_ext_create_only
  in
  test_apply_patches patches [] [ "foo.ml" ];
  [%expect
    {|
    foo.ml:
    Hello World |}]
;;

(* Rename operations now work correctly after fixing prefix parsing. *)
let%expect_test "apply_patches - rename_patch" =
  let patches =
    Dune_patch.For_tests.parse_patches ~loc:Loc.none Patch_examples.rename_patch
  in
  test_apply_patches patches [ "old.ml", "content\n" ] [ "new.ml" ];
  [%expect
    {|
    new.ml:
    content
    |}]
;;
