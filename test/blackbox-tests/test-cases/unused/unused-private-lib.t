Unused export detection in private libraries.

For private libraries (no public_name), ALL exports are checked including
the wrapper module's, since there are no external consumers.

  $ cat > dune-project <<EOF
  > (lang dune 3.23)
  > EOF

  $ cat > dune <<EOF
  > (library
  >  (name private_lib)
  >  (modules private_lib helper))
  > EOF

  $ cat > private_lib.ml <<EOF
  > let x = Helper.used 1
  > let also_unused = 99
  > EOF

  $ cat > private_lib.mli <<EOF
  > val x : int
  > val also_unused : int
  > EOF

  $ cat > helper.ml <<EOF
  > let used x = x + 1
  > let not_used x = x - 1
  > EOF

  $ cat > helper.mli <<EOF
  > val used : int -> int
  > val not_used : int -> int
  > EOF

Should report not_used (internal), and x and also_unused (wrapper of private lib):

  $ dune build @unused
  File "helper.mli", line 2, characters 4-12:
  2 | val not_used : int -> int
          ^^^^^^^^
  Error: unused export not_used
  File "private_lib.mli", line 1, characters 4-5:
  1 | val x : int
          ^
  Error: unused export x
  File "private_lib.mli", line 2, characters 4-15:
  2 | val also_unused : int
          ^^^^^^^^^^^
  Error: unused export also_unused
  [1]
