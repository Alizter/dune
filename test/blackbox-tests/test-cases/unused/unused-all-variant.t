@unused skips public wrapper exports. @unused-all reports everything.

  $ cat > dune-project <<EOF
  > (lang dune 3.23)
  > (package (name mypkg))
  > EOF

  $ cat > dune <<EOF
  > (library
  >  (name mylib)
  >  (public_name mypkg.mylib)
  >  (modules mylib helper))
  > EOF

  $ cat > mylib.ml <<EOF
  > let pub_used = Helper.used 1
  > let pub_unused = 42
  > EOF

  $ cat > mylib.mli <<EOF
  > val pub_used : int
  > val pub_unused : int
  > EOF

  $ cat > helper.ml <<EOF
  > let used x = x + 1
  > let dead x = x * 2
  > EOF

  $ cat > helper.mli <<EOF
  > val used : int -> int
  > val dead : int -> int
  > EOF

@unused skips public wrapper exports. Only reports dead:

  $ dune build @unused
  File "helper.mli", line 2, characters 4-8:
  2 | val dead : int -> int
          ^^^^
  Error: unused export dead
  [1]

@unused-all also reports wrapper exports (pub_used and pub_unused are
both unused from outside this cctx):

  $ dune build @unused-all
  File "helper.mli", line 2, characters 4-8:
  2 | val dead : int -> int
          ^^^^
  Error: unused export dead
  File "mylib.mli", line 1, characters 4-12:
  1 | val pub_used : int
          ^^^^^^^^
  Error: unused export pub_used
  File "mylib.mli", line 2, characters 4-14:
  2 | val pub_unused : int
          ^^^^^^^^^^
  Error: unused export pub_unused
  [1]
