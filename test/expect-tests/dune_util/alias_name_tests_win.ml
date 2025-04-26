let%expect_test "windows_tests" =
  test_path "C:\\foo";
  [%expect {| ❌ User error: "C:\\foo" is an invalid alias name. |}];
  test_path "C:\\foo\\bar";
  [%expect {| ❌ User error: "C:\\foo\\bar" is an invalid alias name. |}];
  test_path "C:\\foo\\bar@";
  [%expect {| ❌ User error: "C:\\foo\\bar@" is an invalid alias name. |}];
  test_path "C:\\foo\\@bar";
  [%expect {| ❌ User error: "C:\\foo\\@bar" is an invalid alias name. |}];
  test_path "foo/lib:baz";
  [%expect {| ✅ { dir = "foo"; alias_name = "lib:baz" } |}];
  (* TODO: on Windows will be different *)
  test_path "foo\\bar";
  [%expect {| ❌ User error: "foo\\bar" is an invalid alias name. |}];
  (* TODO: on Windows will be different *)
  test_path ".\\";
  [%expect {| ❌ User error: ".\\" is an invalid alias name. |}]
;;
