Test fine-grained cache with chained UNWRAPPED library dependencies.

This creates 3 unwrapped libraries with 4 modules each, where lib_k.mod_i
depends only on lib_{k-1}.mod_i. We compare three scenarios:
1. No cache
2. Regular dune cache
3. Fine-grained cache (on top of regular cache)

=== Create chain of 3 unwrapped libraries with 4 modules each ===

Library structure:
- lib1: lib1_mod_1..4 (no deps)
- lib2: lib2_mod_1..4 (each depends on corresponding lib1 module)
- lib3: lib3_mod_1..4 (each depends on corresponding lib2 module)

  $ create_unwrapped_library lib1 4
  $ create_unwrapped_library lib2 4 lib1
  $ create_unwrapped_library lib3 4 lib2

=== Part 1: No cache ===

  $ export DUNE_CACHE=disabled
  $ export DUNE_CONFIG__FINE_GRAINED_OCAML_CACHE=disabled

Initial build:

  $ dune build 2>&1 | head -20
  $ count_compiled_byte
  12

After clean, everything recompiles (no cache):

  $ dune clean
  $ dune build 2>&1 | head -20
  $ echo "No cache, after clean:"
  No cache, after clean:
  $ count_compiled_byte
  12

Change lib1_mod_1's IMPLEMENTATION (not interface):

  $ cat > lib1/lib1_mod_1.ml << EOF
  > let value = 100
  > EOF

  $ dune clean
  $ dune build 2>&1 | head -20
  $ echo "No cache, after impl change:"
  No cache, after impl change:
  $ count_compiled_byte
  12

Change lib1_mod_1's INTERFACE:

  $ cat > lib1/lib1_mod_1.mli << EOF
  > val value : int
  > val extra : string
  > EOF

  $ cat > lib1/lib1_mod_1.ml << EOF
  > let value = 100
  > let extra = "new"
  > EOF

  $ dune clean
  $ dune build 2>&1 | head -20
  $ echo "No cache, after interface change:"
  No cache, after interface change:
  $ count_compiled_byte
  12

=== Part 2: Regular dune cache ===

  $ export DUNE_CACHE=enabled
  $ export DUNE_CONFIG__FINE_GRAINED_OCAML_CACHE=disabled

Reset to original:

  $ cat > lib1/lib1_mod_1.mli << EOF
  > val value : int
  > EOF

  $ cat > lib1/lib1_mod_1.ml << EOF
  > let value = 1
  > EOF

Populate the cache:

  $ dune clean
  $ dune build 2>&1 | head -20
  $ count_compiled_byte
  12

After clean, cache restores everything:

  $ dune clean
  $ dune build 2>&1 | head -20
  $ echo "Regular cache, after clean:"
  Regular cache, after clean:
  $ count_compiled_byte
  0

Change lib1_mod_1's IMPLEMENTATION (not interface):

  $ cat > lib1/lib1_mod_1.ml << EOF
  > let value = 100
  > EOF

  $ dune clean
  $ dune build 2>&1 | head -20
  $ echo "Regular cache, after impl change:"
  Regular cache, after impl change:
  $ count_compiled_byte
  1

Only 1 module recompiles - regular cache handles implementation changes well.

Reset and change lib1_mod_1's INTERFACE:

  $ cat > lib1/lib1_mod_1.ml << EOF
  > let value = 1
  > EOF

  $ dune clean
  $ dune build 2>&1 | head -20

  $ cat > lib1/lib1_mod_1.mli << EOF
  > val value : int
  > val extra : string
  > EOF

  $ cat > lib1/lib1_mod_1.ml << EOF
  > let value = 100
  > let extra = "new"
  > EOF

  $ dune clean
  $ dune build 2>&1 | head -20
  $ echo "Regular cache, after interface change:"
  Regular cache, after interface change:
  $ count_compiled_byte
  9

Regular cache recompiles 9 modules: lib1_mod_1 + all of lib2 and lib3
because dune tracks at library level (lib1 changed → recompile all dependents).

  $ show_compiled_byte
    lib1/lib1_mod_1.ml
    lib2/lib2_mod_1.ml
    lib2/lib2_mod_2.ml
    lib2/lib2_mod_3.ml
    lib2/lib2_mod_4.ml
    lib3/lib3_mod_1.ml
    lib3/lib3_mod_2.ml
    lib3/lib3_mod_3.ml
    lib3/lib3_mod_4.ml

=== Part 3: Fine-grained cache ===

  $ export DUNE_CACHE=enabled
  $ export DUNE_CONFIG__FINE_GRAINED_OCAML_CACHE=enabled

Reset to original:

  $ cat > lib1/lib1_mod_1.mli << EOF
  > val value : int
  > EOF

  $ cat > lib1/lib1_mod_1.ml << EOF
  > let value = 1
  > EOF

Populate the fine-grained cache:

  $ dune clean
  $ dune build 2>&1 | head -20
  $ count_compiled_byte
  12

After clean, cache restores everything:

  $ dune clean
  $ dune build 2>&1 | head -20
  $ echo "Fine-grained cache, after clean:"
  Fine-grained cache, after clean:
  $ count_compiled_byte
  0

Change lib1_mod_1's IMPLEMENTATION (not interface):

  $ cat > lib1/lib1_mod_1.ml << EOF
  > let value = 100
  > EOF

  $ dune clean
  $ dune build 2>&1 | head -20
  $ echo "Fine-grained cache, after impl change:"
  Fine-grained cache, after impl change:
  $ count_compiled_byte
  1

Reset and change lib1_mod_1's INTERFACE:

  $ cat > lib1/lib1_mod_1.ml << EOF
  > let value = 1
  > EOF

  $ dune clean
  $ dune build 2>&1 | head -20

  $ cat > lib1/lib1_mod_1.mli << EOF
  > val value : int
  > val extra : string
  > EOF

  $ cat > lib1/lib1_mod_1.ml << EOF
  > let value = 200
  > let extra = "new"
  > EOF

  $ dune clean
  $ dune build 2>&1 | head -20
  $ echo "Fine-grained cache, after interface change:"
  Fine-grained cache, after interface change:
  $ count_compiled_byte
  2

  $ show_compiled_byte
    lib1/lib1_mod_1.ml
    lib2/lib2_mod_1.ml

Only 2 modules recompile because fine-grained cache tracks actual module
dependencies (from ocamlobjinfo), not library-level dependencies.

=== Summary ===

| Scenario                    | No Cache | Regular Cache | Fine-Grained |
|-----------------------------|----------|---------------|--------------|
| After clean                 | 12       | 0             | 0            |
| After impl change           | 12       | 1             | 1            |
| After interface change      | 12       | 9             | 2            |

The fine-grained cache provides additional savings over the regular cache
when interfaces change, by tracking actual module-level dependencies.
For implementation-only changes, both caches perform equally well.

