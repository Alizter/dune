When all exports are referenced, @unused should succeed silently.

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
  > let result = Helper.add 1 2
  > EOF

  $ cat > mylib.mli <<EOF
  > val result : int
  > EOF

  $ cat > helper.ml <<EOF
  > let add x y = x + y
  > EOF

  $ cat > helper.mli <<EOF
  > val add : int -> int -> int
  > EOF

  $ dune build @unused
