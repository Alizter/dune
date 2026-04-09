Unused export detection in executables.

Internal modules' .mli exports that are not referenced by any other module
in the executable should be reported.

  $ cat > dune-project <<EOF
  > (lang dune 3.23)
  > EOF

  $ cat > dune <<EOF
  > (executable
  >  (name main)
  >  (modules main util))
  > EOF

  $ cat > main.ml <<EOF
  > let () = print_int (Util.used_fn 42)
  > EOF

  $ cat > util.ml <<EOF
  > let used_fn x = x + 1
  > let dead_fn x = x * 2
  > EOF

  $ cat > util.mli <<EOF
  > val used_fn : int -> int
  > val dead_fn : int -> int
  > EOF

Should report dead_fn:

  $ dune build @unused
  File "util.mli", line 2, characters 4-11:
  2 | val dead_fn : int -> int
          ^^^^^^^
  Error: unused export dead_fn
  [1]
