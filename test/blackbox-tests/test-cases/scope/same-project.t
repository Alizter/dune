A scope filters packages declared together in one project while retaining the
canonical project long enough to decode their package-owned stanzas.

  $ cat > dune-project <<'EOF'
  > (lang dune 3.22)
  > (using unreleased 0.1)
  > (package (name visible))
  > (package (name hidden))
  > EOF
  $ cat > dune <<'EOF'
  > (scope
  >  (packages visible))
  > (library
  >  (name visible)
  >  (public_name visible)
  >  (modules Visible))
  > (library
  >  (name hidden)
  >  (public_name hidden)
  >  (modules Hidden))
  > (executable
  >  (name main)
  >  (modules Main)
  >  (libraries visible))
  > (executable
  >  (name hidden_main)
  >  (modules Hidden_main)
  >  (libraries hidden))
  > EOF
  $ echo 'let message = "visible package"' > visible.ml
  $ echo 'let message = "hidden package"' > hidden.ml
  $ echo 'let () = print_endline Visible.message' > main.ml
  $ echo 'let () = print_endline Hidden.message' > hidden_main.ml

  $ dune exec ./main.exe
  visible package

  $ dune build ./hidden_main.exe 2> error
  [1]
  $ grep -F 'Library "hidden" not found' error
  Error: Library "hidden" not found.
