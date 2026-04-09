Type exports referenced via annotations should not be reported.
Unused types are reported at the type level. Individual constructors
and fields are skipped (no impl_id in the index).

  $ cat > dune-project <<EOF
  > (lang dune 3.23)
  > (package (name mypkg))
  > EOF

  $ cat > dune <<EOF
  > (library
  >  (name mylib)
  >  (public_name mypkg.mylib)
  >  (modules mylib types))
  > EOF

  $ cat > types.ml <<EOF
  > type point = { x : int; y : int }
  > type color = Red | Green | Blue
  > type unused_type = Foo | Bar
  > EOF

  $ cat > types.mli <<EOF
  > type point = { x : int; y : int }
  > type color = Red | Green | Blue
  > type unused_type = Foo | Bar
  > EOF

  $ cat > mylib.ml <<EOF
  > let origin : Types.point = { x = 0; y = 0 }
  > let favorite = Types.Red
  > EOF

  $ cat > mylib.mli <<EOF
  > val origin : Types.point
  > val favorite : Types.color
  > EOF

point, color are used types. unused_type is not.
Individual constructors (Red, Green, Foo, Bar) and fields (x, y) are
not reported — only the parent type:

  $ dune build @unused
  File "types.mli", line 3, characters 5-16:
  3 | type unused_type = Foo | Bar
           ^^^^^^^^^^^
  Error: unused export unused_type
  [1]
