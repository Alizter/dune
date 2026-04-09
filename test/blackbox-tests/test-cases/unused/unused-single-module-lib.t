Single-module libraries should be analysed. The module is both the
wrapper and the only module.

  $ cat > dune-project <<EOF
  > (lang dune 3.23)
  > EOF

  $ cat > dune <<EOF
  > (library
  >  (name mylib)
  >  (modules mylib))
  > EOF

  $ cat > mylib.ml <<EOF
  > let used_internally = 1
  > let f x = x + used_internally
  > let dead x = x * 2
  > EOF

  $ cat > mylib.mli <<EOF
  > val f : int -> int
  > val dead : int -> int
  > EOF

dead is unused. f is also unused within the cctx (private lib, no consumers):

  $ dune build @unused
  File "mylib.mli", line 1, characters 4-5:
  1 | val f : int -> int
          ^
  Error: unused export f
  File "mylib.mli", line 2, characters 4-8:
  2 | val dead : int -> int
          ^^^^
  Error: unused export dead
  [1]
