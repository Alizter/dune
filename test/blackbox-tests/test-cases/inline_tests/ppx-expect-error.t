  $ cat > dune-project <<EOF
  > (lang dune 3.18)
  > EOF

  $ cat > dune <<EOF
  > (library
  >  (name l)
  >  (preprocess (pps ppx_expect))
  >  (inline_tests))
  > EOF

  $ cat > test.ml <<EOF
  > let foo = 1
  > 
  > (** Invalid doc string *)
  > let%expect_test _ = ()
  > 
  > EOF

The location from the error message is lost.
  $ dune build @runtest
  File "_none_", lines 1-3:
  Error: Attributes not allowed here
  [1]
