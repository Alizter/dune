Exports re-exported via include should not be reported.

When the wrapper does "include Internal", the included values become part
of the public API. The related-uid chain in ocaml-index links them.

  $ cat > dune-project <<EOF
  > (lang dune 3.23)
  > (package (name mypkg))
  > EOF

  $ cat > dune <<EOF
  > (library
  >  (name mylib)
  >  (public_name mypkg.mylib)
  >  (modules mylib base extra))
  > EOF

  $ cat > mylib.ml <<EOF
  > include Base
  > let extra_val = Extra.extra_fn 1
  > EOF

  $ cat > mylib.mli <<EOF
  > val base_fn : int -> int
  > val extra_val : int
  > EOF

  $ cat > base.ml <<EOF
  > let base_fn x = x + 1
  > EOF

  $ cat > base.mli <<EOF
  > val base_fn : int -> int
  > EOF

  $ cat > extra.ml <<EOF
  > let extra_fn x = x + 1
  > let orphan_fn x = x - 1
  > EOF

  $ cat > extra.mli <<EOF
  > val extra_fn : int -> int
  > val orphan_fn : int -> int
  > EOF

base_fn is re-exported via include — not reported.
extra_fn is used by mylib — not reported.
orphan_fn is unused — should be reported:

  $ dune build @unused
  File "extra.mli", line 2, characters 4-13:
  2 | val orphan_fn : int -> int
          ^^^^^^^^^
  Error: unused export orphan_fn
  [1]
