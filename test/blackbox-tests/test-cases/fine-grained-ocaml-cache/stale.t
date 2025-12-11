Test that the fine-grained cache correctly detects stale dependencies.

This tests a scenario where:
1. Module A depends on Module B
2. Build and cache A (compiled against B version 1)
3. Change B's interface
4. Rebuild - A must be recompiled (not get a stale cache hit)

The critical test is that we don't get "inconsistent assumptions" errors
when dependencies change, which would happen if we restored stale cached
artifacts.

  $ export DUNE_CONFIG__FINE_GRAINED_OCAML_CACHE=enabled

Create module B with a function:

  $ cat > dune << EOF
  > (library
  >  (name mylib))
  > EOF

  $ cat > b.mli << EOF
  > val value : int
  > EOF

  $ cat > b.ml << EOF
  > let value = 1
  > EOF

Create module A that depends on B:

  $ cat > a.ml << EOF
  > let x = B.value + 1
  > EOF

=== Build 1: Populate the cache ===

  $ dune build
  $ show_compiled
    a.ml
    b.ml
    mylib.ml-gen

=== Now change B's INTERFACE and rebuild ===

This is the critical test: A was compiled against B's OLD interface.
After changing B's interface, A must be recompiled to avoid
"inconsistent assumptions" errors.

  $ cat > b.mli << EOF
  > val value : int
  > val extra : string
  > EOF

  $ cat > b.ml << EOF
  > let value = 1
  > let extra = "new"
  > EOF

  $ dune clean
  $ dune build
  $ show_compiled
    a.ml
    b.ml
    mylib.ml-gen

A was recompiled (not restored from stale cache). The build succeeds
without "inconsistent assumptions over interface" errors:

  $ echo "Build succeeded"
  Build succeeded
