open Alias_name_tests_utils

(* Forbidden alias names *)
let%expect_test "validate forbidden alias names" =
  test_alias_name "";
  [%expect {| Invalid alias name |}];
  test_alias_name ".";
  [%expect {| Invalid alias name |}];
  test_alias_name "..";
  [%expect {| Invalid alias name |}];
  test_alias_name "/";
  [%expect {| Invalid alias name |}];
  test_alias_name "\\";
  [%expect {| Invalid alias name |}];
  (* TODO: Should these be valid? *)
  test_alias_name "...";
  [%expect {| "..." |}];
  test_alias_name ".@";
  [%expect {| ".@" |}]
;;

(* Alias names that look like paths *)
let%expect_test "validate path-like alias name" =
  test_alias_name "foo";
  [%expect {| "foo" |}];
  test_alias_name ".foo";
  [%expect {| ".foo" |}];
  test_alias_name "..foo";
  [%expect {| "..foo" |}];
  test_alias_name "foo/bar";
  [%expect {| Invalid alias name |}];
  test_alias_name "foo\\bar";
  [%expect {| Invalid alias name |}];
  test_alias_name "/foo";
  [%expect {| Invalid alias name |}];
  test_alias_name "\\foo";
  [%expect {| Invalid alias name |}];
  test_alias_name "foo/";
  [%expect {| Invalid alias name |}];
  test_alias_name "foo\\";
  [%expect {| Invalid alias name |}]
;;

(* Alias names that include a ['@'] are allowed, but not in the first position. *)
let%expect_test "validate alias name with @" =
  test_alias_name "@foo";
  [%expect {| Invalid alias name |}];
  test_alias_name "@@foo";
  [%expect {| Invalid alias name |}];
  test_alias_name "foo@bar";
  [%expect {| "foo@bar" |}]
;;

(* Alias names that include whitespace are forbidden. *)
let%expect_test "validate alias name with whitespace" =
  test_alias_name "foo bar";
  [%expect {| Invalid alias name |}];
  test_alias_name "foo\tbar";
  [%expect {| Invalid alias name |}];
  test_alias_name "foo\nbar";
  [%expect {| Invalid alias name |}];
  test_alias_name "foo\rbar";
  [%expect {| Invalid alias name |}];
  test_alias_name "foo\rbar";
  [%expect {| Invalid alias name |}];
  test_alias_name "foo\012bar";
  [%expect {| Invalid alias name |}]
;;

let%expect_test "validate alias name with parentheses" =
  test_alias_name "foo(bar";
  [%expect {| Invalid alias name |}];
  test_alias_name "(";
  [%expect {| Invalid alias name |}];
  test_alias_name "foo)bar";
  [%expect {| Invalid alias name |}];
  test_alias_name ")";
  [%expect {| Invalid alias name |}];
  test_alias_name "[";
  [%expect {| "[" |}];
  test_alias_name "foo[bar";
  [%expect {| "foo[bar" |}];
  test_alias_name "foo]bar";
  [%expect {| "foo]bar" |}];
  test_alias_name "foo{bar";
  [%expect {| "foo{bar" |}];
  test_alias_name "{";
  [%expect {| "{" |}];
  test_alias_name "foo}bar";
  [%expect {| "foo}bar" |}];
  test_alias_name "}";
  [%expect {| "}" |}]
;;

let%expect_test "validate alias name with special characters" =
  (* We wish to allow `:` in an alias name. *)
  test_alias_name "foo:bar";
  [%expect {| "foo:bar" |}];
  test_alias_name "foo#bar";
  [%expect {| "foo#bar" |}];
  test_alias_name "foo%bar";
  [%expect {| "foo%bar" |}];
  test_alias_name "foo^bar";
  [%expect {| "foo^bar" |}];
  test_alias_name "foo&bar";
  [%expect {| "foo&bar" |}];
  test_alias_name "foo*bar";
  [%expect {| "foo*bar" |}];
  test_alias_name "foo=bar";
  [%expect {| "foo=bar" |}];
  test_alias_name "foo+bar";
  [%expect {| "foo+bar" |}];
  test_alias_name "foo|bar";
  [%expect {| "foo|bar" |}];
  test_alias_name "foo;bar";
  [%expect {| "foo;bar" |}];
  test_alias_name "foo.bar";
  [%expect {| "foo.bar" |}];
  test_alias_name "foo,bar";
  [%expect {| "foo,bar" |}];
  test_alias_name "foo<bar";
  [%expect {| "foo<bar" |}];
  test_alias_name "foo>bar";
  [%expect {| "foo>bar" |}];
  test_alias_name "foo?bar";
  [%expect {| "foo?bar" |}]
;;

(* Parsing alias paths *)

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
