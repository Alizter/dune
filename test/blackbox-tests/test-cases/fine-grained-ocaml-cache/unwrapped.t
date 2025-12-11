Test fine-grained cache with unwrapped libraries and an executable.

This tests cross-library dependency tracking with the simpler exe + lib setup.

Create an UNWRAPPED library with two modules:

  $ mkdir lib
  $ cat > lib/dune << EOF
  > (library
  >  (name mylib)
  >  (wrapped false))
  > EOF

  $ cat > lib/a.mli << EOF
  > val x : int
  > EOF

  $ cat > lib/a.ml << EOF
  > let x = 1
  > EOF

  $ cat > lib/b.mli << EOF
  > val y : int
  > EOF

  $ cat > lib/b.ml << EOF
  > let y = 2
  > EOF

Create an executable that uses A:

  $ cat > dune << EOF
  > (executable
  >  (name main)
  >  (libraries mylib))
  > EOF

  $ cat > main.ml << EOF
  > let () = print_int A.x
  > EOF

=== Build without fine-grained cache ===

  $ export DUNE_CONFIG__FINE_GRAINED_OCAML_CACHE=disabled
  $ dune build 2>&1 | head -5
  $ show_compiled
    lib/a.ml
    lib/b.ml
    main.ml
  $ count_compiled
  5

=== Enable fine-grained cache and populate ===

  $ export DUNE_CONFIG__FINE_GRAINED_OCAML_CACHE=enabled
  $ dune clean
  $ dune build 2>&1 | head -5
  $ show_compiled
    lib/a.ml
    lib/b.ml
    main.ml
  $ count_compiled
  5

=== Clean and rebuild - should get cache hits ===

  $ dune clean
  $ dune build 2>&1 | head -5
  $ show_compiled
  $ count_compiled
  0
  $ show_cache_hits
  # fine-cache HIT (cmo): A - skipping compilation
  # fine-cache HIT (cmo): B - skipping compilation
  # fine-cache HIT (cmx): A - skipping compilation
  # fine-cache HIT (cmx): B - skipping compilation
  # fine-cache HIT (cmx): Main - skipping compilation

All modules including Main get cache hits! (Main only has cmx since it's an executable)

=== Change A's implementation (not interface) ===

  $ cat > lib/a.ml << EOF
  > let x = 100
  > EOF

  $ dune clean
  $ dune build 2>&1 | head -5

Only A should recompile (interface unchanged). Main gets a cache hit because
it only depends on A's interface (a.cmi), not its implementation:

  $ show_compiled
    lib/a.ml
  $ count_compiled
  2
  $ show_cache_hits
  # fine-cache HIT (cmo): B - skipping compilation
  # fine-cache HIT (cmx): B - skipping compilation
  # fine-cache HIT (cmx): Main - skipping compilation

=== Change A's INTERFACE ===

  $ cat > lib/a.mli << EOF
  > val x : int
  > val extra : string
  > EOF

  $ cat > lib/a.ml << EOF
  > let x = 200
  > let extra = "new"
  > EOF

  $ dune clean
  $ dune build 2>&1 | head -5

A and main should recompile (main depends on A's interface):

  $ show_compiled
    lib/a.ml
    main.ml
  $ count_compiled
  3

B correctly gets cache hits since it doesn't depend on A:

  $ show_cache_hits
  # fine-cache HIT (cmo): B - skipping compilation
  # fine-cache HIT (cmx): B - skipping compilation
