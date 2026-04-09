Verify that the cache properly invalidates when source files change.
After adding an unused export and rebuilding, the new export should
be detected.

  $ export DUNE_CACHE_ROOT=$(pwd)/dune_test_cache
  $ mkdir $DUNE_CACHE_ROOT

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
  > let result = Helper.used 1
  > EOF

  $ cat > mylib.mli <<EOF
  > val result : int
  > EOF

  $ cat > helper.ml <<EOF
  > let used x = x + 1
  > EOF

  $ cat > helper.mli <<EOF
  > val used : int -> int
  > EOF

First build: everything is used, @unused should be clean:

  $ dune build @unused

Now add an unused export to helper:

  $ cat > helper.ml <<EOF
  > let used x = x + 1
  > let dead x = x * 2
  > EOF

  $ cat > helper.mli <<EOF
  > val used : int -> int
  > val dead : int -> int
  > EOF

Second build: dead should be reported:

  $ dune build @unused
  File "helper.mli", line 2, characters 4-8:
  2 | val dead : int -> int
          ^^^^
  Error: unused export dead
  [1]
