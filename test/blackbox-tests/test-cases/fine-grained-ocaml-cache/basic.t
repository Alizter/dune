Test the fine-grained OCaml compilation cache feature.

Create a library with two modules A and B:

  $ mkdir lib
  $ cat > lib/dune << EOF
  > (library
  >  (name mylib))
  > EOF

  $ cat > lib/a.ml << EOF
  > let x = 1
  > EOF

  $ cat > lib/b.ml << EOF
  > let y = 2
  > EOF

Create an executable that only uses A:

  $ cat > dune << EOF
  > (executable
  >  (name main)
  >  (libraries mylib))
  > EOF

  $ cat > main.ml << EOF
  > let () = print_int Mylib.A.x
  > EOF

=== BASELINE: Without fine-grained cache ===

First build - everything compiled:

  $ dune build
  $ show_compiled
    lib/a.ml
    lib/b.ml
    lib/mylib.ml-gen
    main.ml

Change B and rebuild - what gets recompiled?

  $ cat > lib/b.ml << EOF
  > let y = 999
  > let z = 99
  > EOF

  $ dune build
  $ show_compiled
    lib/b.ml
    main.ml

Clean and rebuild from scratch:

  $ dune clean
  $ dune build
  $ show_compiled
    lib/a.ml
    lib/b.ml
    lib/mylib.ml-gen
    main.ml

=== WITH fine-grained cache ===

  $ export DUNE_CONFIG__FINE_GRAINED_OCAML_CACHE=enabled

Reset to original B:

  $ cat > lib/b.ml << EOF
  > let y = 2
  > EOF

Build to populate the fine-grained cache:

  $ dune clean
  $ dune build
  $ show_compiled
    lib/a.ml
    lib/b.ml
    lib/mylib.ml-gen
    main.ml

Clean and rebuild - fine-grained cache should restore artifacts:

  $ dune clean
  $ dune build
  $ show_compiled
    lib/a.ml
    lib/b.ml
    lib/mylib.ml-gen

Show which modules had cache hits:

  $ show_cache_hits
  # fine-cache HIT (cmx): A - skipping compilation
  # fine-cache HIT (cmx): B - skipping compilation
  # fine-cache HIT (cmx): Main - skipping compilation

No modules compiled - all restored from fine-grained cache!

Change B and rebuild - only B should recompile, not main (which only uses A):

  $ cat > lib/b.ml << EOF
  > let y = 999
  > let z = 9999
  > EOF

  $ dune build
  $ show_compiled
    lib/b.ml

Main is still a cache hit (it only depends on A's interface, which didn't change):

  $ show_cache_hits
  # fine-cache HIT (cmx): Main - skipping compilation

=== AUDIT: Reproducibility check ===

The reproducibility check verifies cache hits by recompiling and comparing outputs.
Note: We use -j1 because verify mode recompiles, which can conflict with parallel builds.

  $ export DUNE_FINE_CACHE_CHECK=1

Reset B to original and rebuild (cache already has these entries from earlier):

  $ unset DUNE_FINE_CACHE_CHECK
  $ cat > lib/b.ml << EOF
  > let y = 2
  > EOF

  $ dune clean
  $ dune build
  $ show_compiled
    lib/a.ml
    lib/b.ml
    lib/mylib.ml-gen

Clean and rebuild with audit enabled (single-threaded):

  $ export DUNE_FINE_CACHE_CHECK=1
  $ dune clean
  $ dune build -j1
  $ show_audit
  # fine-cache VERIFIED (cmx): A - outputs match
  # fine-cache VERIFIED (cmx): B - outputs match
  # fine-cache VERIFIED (cmx): Main - outputs match
  # fine-cache VERIFY (cmx): A - recompiling to check
  # fine-cache VERIFY (cmx): B - recompiling to check
  # fine-cache VERIFY (cmx): Main - recompiling to check

All cache hits verified - outputs match what was cached!
