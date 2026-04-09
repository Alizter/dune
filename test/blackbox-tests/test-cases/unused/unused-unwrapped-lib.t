Unwrapped libraries should be skipped by @unused.

All modules are directly exported to consumers, so we cannot determine
if their exports are unused without cross-boundary analysis.

  $ cat > dune-project <<EOF
  > (lang dune 3.23)
  > EOF

  $ cat > dune <<EOF
  > (library
  >  (name mylib)
  >  (wrapped false)
  >  (modules foo bar))
  > EOF

  $ cat > foo.ml <<EOF
  > let f x = x + 1
  > EOF

  $ cat > foo.mli <<EOF
  > val f : int -> int
  > EOF

  $ cat > bar.ml <<EOF
  > let g x = x * 2
  > EOF

  $ cat > bar.mli <<EOF
  > val g : int -> int
  > EOF

No reports — unwrapped library is skipped:

  $ dune build @unused
