@unused works across multiple stanzas. Each gets its own analysis.

  $ cat > dune-project <<EOF
  > (lang dune 3.23)
  > (package (name mypkg))
  > EOF

  $ mkdir -p lib exe

  $ cat > lib/dune <<EOF
  > (library
  >  (name mylib)
  >  (public_name mypkg.mylib)
  >  (modules mylib internal))
  > EOF

  $ cat > lib/mylib.ml <<EOF
  > let f = Internal.used
  > EOF

  $ cat > lib/mylib.mli <<EOF
  > val f : int -> int
  > EOF

  $ cat > lib/internal.ml <<EOF
  > let used x = x + 1
  > let lib_dead x = x * 2
  > EOF

  $ cat > lib/internal.mli <<EOF
  > val used : int -> int
  > val lib_dead : int -> int
  > EOF

  $ cat > exe/dune <<EOF
  > (executable
  >  (name main)
  >  (modules main util)
  >  (libraries mylib))
  > EOF

  $ cat > exe/main.ml <<EOF
  > let () = print_int (Mylib.f (Util.helper 1))
  > EOF

  $ cat > exe/util.ml <<EOF
  > let helper x = x + 1
  > let exe_dead x = x - 1
  > EOF

  $ cat > exe/util.mli <<EOF
  > val helper : int -> int
  > val exe_dead : int -> int
  > EOF

Should report lib_dead and exe_dead:

  $ dune build @unused
  File "exe/util.mli", line 2, characters 4-12:
  2 | val exe_dead : int -> int
          ^^^^^^^^
  Error: unused export exe_dead
  File "lib/internal.mli", line 2, characters 4-12:
  2 | val lib_dead : int -> int
          ^^^^^^^^
  Error: unused export lib_dead
  [1]

Per-directory: only lib:

  $ dune build @lib/unused
  File "lib/internal.mli", line 2, characters 4-12:
  2 | val lib_dead : int -> int
          ^^^^^^^^
  Error: unused export lib_dead
  [1]

Per-directory: only exe:

  $ dune build @exe/unused
  File "exe/util.mli", line 2, characters 4-12:
  2 | val exe_dead : int -> int
          ^^^^^^^^
  Error: unused export exe_dead
  [1]
