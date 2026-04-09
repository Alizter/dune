Exports re-exported through the wrapper should not be reported.

When the wrapper uses a value from an internal module (directly or via
include/module alias), that value is part of the library's public API
and should not be flagged.

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

The wrapper re-exports Internal.public_fn but not private_fn:

  $ cat > mylib.ml <<EOF
  > let public_fn = Internal.public_fn
  > EOF

  $ cat > mylib.mli <<EOF
  > val public_fn : int -> int
  > EOF

  $ cat > internal.ml <<EOF
  > let public_fn x = x + 1
  > let private_fn x = x * 2
  > EOF

  $ cat > internal.mli <<EOF
  > val public_fn : int -> int
  > val private_fn : int -> int
  > EOF

Should report only private_fn. public_fn is used by the wrapper:

  $ dune build @unused
  File "internal.mli", line 2, characters 4-14:
  2 | val private_fn : int -> int
          ^^^^^^^^^^
  Error: unused export private_fn
  [1]
