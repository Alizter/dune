open Stdune
open Dune_util

let test s =
  match Alias_name.of_string_opt s with
  | Some a -> a |> Alias_name.to_dyn |> Dyn.pp |> Format.printf "%a\n" Pp.to_fmt
  | None -> Printf.printf "Invalid alias name\n"
;;

(* Forbidden alias names *)
let%expect_test "validate forbidden alias names" =
  test "";
  [%expect {| Invalid alias name |}];
  test ".";
  [%expect {| Invalid alias name |}];
  test "..";
  [%expect {| Invalid alias name |}];
  test "/";
  [%expect {| Invalid alias name |}];
  test "\\";
  [%expect {| Invalid alias name |}];
  (* TODO: Should these be valid? *)
  test "...";
  [%expect {| "..." |}];
  test ".@";
  [%expect {| ".@" |}]
;;

(* Alias names that look like paths *)
let%expect_test "validate path-like alias name" =
  test "foo";
  [%expect {| "foo" |}];
  test ".foo";
  [%expect {| ".foo" |}];
  test "..foo";
  [%expect {| "..foo" |}];
  test "foo/bar";
  [%expect {| Invalid alias name |}];
  test "foo\\bar";
  [%expect {| Invalid alias name |}];
  test "/foo";
  [%expect {| Invalid alias name |}];
  test "\\foo";
  [%expect {| Invalid alias name |}];
  test "foo/";
  [%expect {| Invalid alias name |}];
  test "foo\\";
  [%expect {| Invalid alias name |}]
;;

(* Alias names that include a ['@'] are allowed, but not in the first position. *)
let%expect_test "validate alias name with @" =
  test "@foo";
  [%expect {| Invalid alias name |}];
  test "@@foo";
  [%expect {| Invalid alias name |}];
  test "foo@bar";
  [%expect {| "foo@bar" |}]
;;

(* Alias names that include whitespace are forbidden. *)
let%expect_test "validate alias name with whitespace" =
  test "foo bar";
  [%expect {| Invalid alias name |}];
  test "foo\tbar";
  [%expect {| Invalid alias name |}];
  test "foo\nbar";
  [%expect {| Invalid alias name |}];
  test "foo\rbar";
  [%expect {| Invalid alias name |}];
  test "foo\rbar";
  [%expect {| Invalid alias name |}];
  test "foo\012bar";
  [%expect {| Invalid alias name |}]
;;

let%expect_test "validate alias name with parentheses" =
  test "foo(bar";
  [%expect {| Invalid alias name |}];
  test "(";
  [%expect {| Invalid alias name |}];
  test "foo)bar";
  [%expect {| Invalid alias name |}];
  test ")";
  [%expect {| Invalid alias name |}];
  test "[";
  [%expect {| "[" |}];
  test "foo[bar";
  [%expect {| "foo[bar" |}];
  test "foo]bar";
  [%expect {| "foo]bar" |}];
  test "foo{bar";
  [%expect {| "foo{bar" |}];
  test "{";
  [%expect {| "{" |}];
  test "foo}bar";
  [%expect {| "foo}bar" |}];
  test "}";
  [%expect {| "}" |}]
;;

let%expect_test "validate alias name with special characters" =
  (* We wish to allow `:` in an alias name. *)
  test "foo:bar";
  [%expect {| "foo:bar" |}];
  test "foo#bar";
  [%expect {| "foo#bar" |}];
  test "foo%bar";
  [%expect {| "foo%bar" |}];
  test "foo^bar";
  [%expect {| "foo^bar" |}];
  test "foo&bar";
  [%expect {| "foo&bar" |}];
  test "foo*bar";
  [%expect {| "foo*bar" |}];
  test "foo=bar";
  [%expect {| "foo=bar" |}];
  test "foo+bar";
  [%expect {| "foo+bar" |}];
  test "foo|bar";
  [%expect {| "foo|bar" |}];
  test "foo;bar";
  [%expect {| "foo;bar" |}];
  test "foo.bar";
  [%expect {| "foo.bar" |}];
  test "foo,bar";
  [%expect {| "foo,bar" |}];
  test "foo<bar";
  [%expect {| "foo<bar" |}];
  test "foo>bar";
  [%expect {| "foo>bar" |}];
  test "foo?bar";
  [%expect {| "foo?bar" |}]
;;

(* Parsing alias paths *)

let test_path s =
  match Alias_name.parse_local_path (Loc.none, Path.Local.of_string s) with
  | dir, name ->
    Printf.printf
      "✅ %s"
      (Dyn.record [ "dir", Path.Local.to_dyn dir; "alias_name", Alias_name.to_dyn name ]
       |> Dyn.to_string)
  | exception User_error.E e ->
    Printf.printf
      "❌ User error: %s\n"
      ({ e with paragraphs = [ List.hd e.paragraphs ] } |> User_message.to_string)
  | exception Code_error.E e ->
    Printf.printf "💀 Code error: %s\n" (Code_error.to_dyn_without_loc e |> Dyn.to_string)
;;

let%expect_test "valid paths" =
  test_path "";
  [%expect {| ❌ User error: Invalid alias path: "." |}];
  test_path "foo";
  [%expect {| ✅ { dir = "."; alias_name = "foo" } |}];
  test_path "foo/bar";
  [%expect {| ✅ { dir = "foo"; alias_name = "bar" } |}];
  test_path "foo/bar@";
  [%expect {| ✅ { dir = "foo"; alias_name = "bar@" } |}];
  test_path "foo/@bar";
  [%expect {| ❌ User error: "@bar" is an invalid alias name. |}];
  test_path "foo\\bar";
  [%expect {| ❌ User error: "foo\\bar" is an invalid alias name. |}];
  test_path "./";
  [%expect {| ❌ User error: Invalid alias path: "." |}];
  test_path "foo";
  [%expect {| ✅ { dir = "."; alias_name = "foo" } |}];
  test_path "foo/bar/baz";
  [%expect {| ✅ { dir = "foo/bar"; alias_name = "baz" } |}];
  test_path "foo/bar/../baz";
  [%expect {| ✅ { dir = "foo"; alias_name = "baz" } |}]
;;

let%expect_test "windows_tests" =
  test_path "C:\\foo";
  [%expect {| ❌ User error: "C:\\foo" is an invalid alias name. |}];
  test_path "C:\\foo\\bar";
  [%expect {| ❌ User error: "C:\\foo\\bar" is an invalid alias name. |}];
  test_path "C:\\foo\\bar@";
  [%expect {| ❌ User error: "C:\\foo\\bar@" is an invalid alias name. |}];
  test_path "C:\\foo\\@bar";
  [%expect {| ❌ User error: "C:\\foo\\@bar" is an invalid alias name. |}]
;;

let%expect_test "absolute paths" =
  test_path "\\";
  [%expect {| ❌ User error: "\\" is an invalid alias name. |}];
  (* TODO: on Windows will be different *)
  test_path "foo\\bar";
  [%expect {| ❌ User error: "foo\\bar" is an invalid alias name. |}];
  (* TODO: on Windows will be different *)
  test_path "C:\\";
  [%expect {| ❌ User error: "C:\\" is an invalid alias name. |}];
  (* TODO: on Windows will be different *)
  test_path ".\\";
  [%expect {| ❌ User error: ".\\" is an invalid alias name. |}]
;;
