Virtual libraries should be skipped by @unused.

  $ cat > dune-project <<EOF
  > (lang dune 3.23)
  > EOF

  $ cat > dune <<EOF
  > (library
  >  (name vlib)
  >  (virtual_modules backend)
  >  (modules vlib backend))
  > EOF

  $ cat > vlib.ml <<EOF
  > let run () = Backend.process 42
  > EOF

  $ cat > vlib.mli <<EOF
  > val run : unit -> int
  > EOF

  $ cat > backend.mli <<EOF
  > val process : int -> int
  > EOF

  $ dune build @unused
