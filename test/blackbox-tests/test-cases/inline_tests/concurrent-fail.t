Failing inline tests shouldn't hinder the diffing or promotion of other tests.

  $ cat >dune-project <<EOF
  > (lang dune 3.7)
  > EOF

  $ cat > dune << EOF
  > (library
  >  (name test)
  >  (inline_tests)
  >  (wrapped false)
  >  (preprocess (pps ppx_expect)))
  > EOF

  $ cat > print.ml << EOF
  > let f = Printf.printf
  > EOF

We have two files with an inline test.
  $ cat > test1.ml << EOF
  > let%expect_test "test1" = Print.f "hello"; [%expect {| |}]
  > EOF

  $ cat > test2.ml << EOF
  > let%expect_test "test1" = Print.f "hello"; [%expect {| |}]
  > EOF

Both tests fail.
  $ dune test
  File "test1.ml", line 1, characters 0-0:
  Error: Files _build/default/test1.ml and _build/default/test1.ml.corrected
  differ.
  File "test2.ml", line 1, characters 0-0:
  Error: Files _build/default/test2.ml and _build/default/test2.ml.corrected
  differ.
  [1]

Both are registered for promotion.
  $ dune promote
  Promoting _build/default/test1.ml.corrected to test1.ml.
  Promoting _build/default/test2.ml.corrected to test2.ml.

  $ cat test1.ml
  let%expect_test "test1" = Print.f "hello"; [%expect {| hello |}]
  $ cat test2.ml
  let%expect_test "test1" = Print.f "hello"; [%expect {| hello |}]
