A library whose exports are only used internally (within the same cctx)
and not by any other stanza. All internal references should still be
detected correctly.

  $ cat > dune-project <<EOF
  > (lang dune 3.23)
  > EOF

  $ cat > dune <<EOF
  > (library
  >  (name mylib)
  >  (modules mylib a b))
  > EOF

  $ cat > mylib.ml <<EOF
  > let result = A.fn_a (B.fn_b 1)
  > EOF

  $ cat > mylib.mli <<EOF
  > val result : int
  > EOF

  $ cat > a.ml <<EOF
  > let fn_a x = x + 1
  > let dead_a x = x * 3
  > EOF

  $ cat > a.mli <<EOF
  > val fn_a : int -> int
  > val dead_a : int -> int
  > EOF

  $ cat > b.ml <<EOF
  > let fn_b x = x * 2
  > let dead_b x = x - 1
  > EOF

  $ cat > b.mli <<EOF
  > val fn_b : int -> int
  > val dead_b : int -> int
  > EOF

fn_a and fn_b are used by the wrapper. dead_a and dead_b are unused.
mylib.result is a wrapper export of a private lib with no external consumers:

  $ dune build @unused
  File "a.mli", line 2, characters 4-10:
  2 | val dead_a : int -> int
          ^^^^^^
  Error: unused export dead_a
  File "b.mli", line 2, characters 4-10:
  2 | val dead_b : int -> int
          ^^^^^^
  Error: unused export dead_b
  File "mylib.mli", line 1, characters 4-10:
  1 | val result : int
          ^^^^^^
  Error: unused export result
  [1]
