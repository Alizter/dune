Test that warnings should be replayed on null builds

This test demonstrates the problem: when we disable warn-error to allow
warnings without failing, the warnings disappear on null builds.

  $ cat >dune-project <<EOF
  > (lang dune 3.0)
  > EOF

  $ cat >dune <<EOF
  > (library
  >  (name foo)
  >  (flags :standard -warn-error -A))
  > EOF

  $ cat >foo.ml <<EOF
  > let unused = 42
  > let f x = x + 1
  > EOF

  $ cat >foo.mli <<EOF
  > val f : int -> int
  > EOF

First build - warning appears twice (once from process, once replayed):

  $ dune build
  File "foo.ml", line 1, characters 4-10:
  1 | let unused = 42
          ^^^^^^
  Warning 32 [unused-value-declaration]: unused value unused.
  
  File "foo.ml", line 1, characters 4-10:
  1 | let unused = 42
          ^^^^^^
  Warning 32 [unused-value-declaration]: unused value unused.
  


Second build (null build) - warning DOES appear (replayed from cache!):

  $ dune build
  File "foo.ml", line 1, characters 4-10:
  1 | let unused = 42
          ^^^^^^
  Warning 32 [unused-value-declaration]: unused value unused.
  
  File "foo.ml", line 1, characters 4-10:
  1 | let unused = 42
          ^^^^^^
  Warning 32 [unused-value-declaration]: unused value unused.
  

