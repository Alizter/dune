Exports used by other stanzas in the workspace should not be reported.
Cross-cctx merging aggregates impl references from dependent stanzas.

  $ cat > dune-project <<EOF
  > (lang dune 3.23)
  > EOF

  $ mkdir -p baselib consumer

  $ cat > baselib/dune <<EOF
  > (library
  >  (name baselib)
  >  (modules baselib helper))
  > EOF

  $ cat > baselib/baselib.ml <<EOF
  > let pub = Helper.used
  > EOF

  $ cat > baselib/baselib.mli <<EOF
  > val pub : int -> int
  > EOF

  $ cat > baselib/helper.ml <<EOF
  > let used x = x + 1
  > let dead x = x * 2
  > EOF

  $ cat > baselib/helper.mli <<EOF
  > val used : int -> int
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

Baselib.pub IS used by consumer — should NOT be reported.
Helper.dead is genuinely unused — should be reported.

  $ dune build @unused
  File "baselib/helper.mli", line 2, characters 4-8:
  2 | val dead : int -> int
          ^^^^
  Error: unused export dead
  [1]
