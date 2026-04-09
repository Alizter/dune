Unused export detection in wrapped libraries.

Internal modules' .mli exports that are not referenced by any other module
in the library should be reported. Exports used by other modules (including
the wrapper) should not be reported.

  $ cat > dune-project <<EOF
  > (lang dune 3.23)
  > (package (name mypkg))
  > EOF

  $ cat > dune <<EOF
  > (library
  >  (name mylib)
  >  (public_name mypkg.mylib)
  >  (modules mylib helper dead))
  > EOF

The wrapper uses Helper.used_fn but nothing from Dead:

  $ cat > mylib.ml <<EOF
  > let result = Helper.used_fn 42
  > EOF

  $ cat > mylib.mli <<EOF
  > val result : int
  > EOF

Helper exports used_fn (referenced by mylib) and unused_fn (referenced by nobody):

  $ cat > helper.ml <<EOF
  > let used_fn x = x + 1
  > let unused_fn x = x * 2
  > EOF

  $ cat > helper.mli <<EOF
  > val used_fn : int -> int
  > val unused_fn : int -> int
  > EOF

Dead exports dead_fn which nobody calls:

  $ cat > dead.ml <<EOF
  > let dead_fn x = x - 1
  > EOF

  $ cat > dead.mli <<EOF
  > val dead_fn : int -> int
  > EOF

Should report unused_fn and dead_fn:

  $ dune build @unused
  File "dead.mli", line 1, characters 4-11:
  1 | val dead_fn : int -> int
          ^^^^^^^
  Error: unused export dead_fn
  File "helper.mli", line 2, characters 4-13:
  2 | val unused_fn : int -> int
          ^^^^^^^^^
  Error: unused export unused_fn
  [1]
