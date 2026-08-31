A package with an explicit dir belongs to the scope at that directory.

  $ cat > dune-project <<'EOF'
  > (lang dune 3.22)
  > (using unreleased 0.1)
  > (package
  >  (name selected)
  >  (dir selected))
  > (package
  >  (name hidden)
  >  (dir hidden))
  > EOF
  $ cat > dune <<'EOF'
  > (executable
  >  (name main)
  >  (modules Main)
  >  (libraries selected))
  > (executable
  >  (name hidden_main)
  >  (modules Hidden_main)
  >  (libraries hidden))
  > EOF
  $ cat > main.ml <<'EOF'
  > let () = print_endline Selected.message
  > EOF
  $ echo 'let () = ()' > hidden_main.ml

  $ mkdir selected hidden
  $ cat > selected/dune <<'EOF'
  > (scope
  >  (packages selected))
  > (library
  >  (name selected)
  >  (public_name selected))
  > EOF
  $ echo 'let message = "selected package dir"' > selected/selected.ml

  $ cat > hidden/dune <<'EOF'
  > (scope
  >  (packages))
  > (library
  >  (name hidden)
  >  (public_name hidden))
  > EOF
  $ echo 'let message = "hidden package dir"' > hidden/hidden.ml

  $ dune exec ./main.exe
  selected package dir

  $ dune build ./hidden_main.exe 2> error
  [1]
  $ grep -F 'Library "hidden" not found' error
  Error: Library "hidden" not found.
