Unused export detection in public libraries.

For public libraries, the wrapper module's exports are excluded from
analysis since external consumers may use them. Internal module exports
are still checked.

  $ cat > dune-project <<EOF
  > (lang dune 3.23)
  > (package (name mypkg))
  > EOF

  $ cat > dune <<EOF
  > (library
  >  (name mylib)
  >  (public_name mypkg.mylib)
  >  (modules mylib internal))
  > EOF

  $ cat > mylib.ml <<EOF
  > let pub_fn = Internal.used
  > let pub_unused = 42
  > EOF

  $ cat > mylib.mli <<EOF
  > val pub_fn : int -> int
  > val pub_unused : int
  > EOF

  $ cat > internal.ml <<EOF
  > let used x = x + 1
  > let dead x = x * 2
  > EOF

  $ cat > internal.mli <<EOF
  > val used : int -> int
  > val dead : int -> int
  > EOF

pub_fn and pub_unused are wrapper exports in a public lib — not reported.
dead is an internal module export unused within the lib — reported:

  $ dune build @unused
  File "internal.mli", line 2, characters 4-8:
  2 | val dead : int -> int
          ^^^^
  Error: unused export dead
  [1]
