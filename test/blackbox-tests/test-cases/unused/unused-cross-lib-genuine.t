A library with downstream consumers should still report genuinely
unused exports. The cross-cctx merge should NOT suppress everything.

  $ cat > dune-project <<EOF
  > (lang dune 3.23)
  > EOF

  $ mkdir -p baselib consumer

baselib exports pub (used by consumer) and dead (used by nobody):

  $ cat > baselib/dune <<EOF
  > (library
  >  (name baselib)
  >  (modules baselib))
  > EOF

  $ cat > baselib/baselib.ml <<EOF
  > let pub x = x + 1
  > let dead x = x * 2
  > EOF

  $ cat > baselib/baselib.mli <<EOF
  > val pub : int -> int
  > val dead : int -> int
  > EOF

  $ cat > consumer/dune <<EOF
  > (executable
  >  (name main)
  >  (libraries baselib))
  > EOF

  $ cat > consumer/main.ml <<EOF
  > let () = print_int (Baselib.pub 42)
  > EOF

dead is genuinely unused across the entire workspace.
pub is used by consumer.

  $ dune build @unused
  File "baselib/baselib.mli", line 2, characters 4-8:
  2 | val dead : int -> int
          ^^^^
  Error: unused export dead
  [1]
