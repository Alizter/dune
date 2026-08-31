A scope inside a subdir stanza applies to that logical subdirectory, so the
scope stanza itself needs no dir field.

  $ cat > dune-project <<'EOF'
  > (lang dune 3.22)
  > (using unreleased 0.1)
  > (package (name app))
  > EOF
  $ cat > dune <<'EOF'
  > (subdir hidden
  >  (scope
  >   (packages)))
  > (executable
  >  (name main)
  >  (libraries hidden))
  > EOF
  $ echo 'let () = ()' > main.ml

  $ mkdir hidden
  $ cat > hidden/dune-project <<'EOF'
  > (lang dune 3.22)
  > (package (name hidden))
  > EOF
  $ cat > hidden/dune <<'EOF'
  > (library
  >  (name hidden)
  >  (public_name hidden))
  > EOF
  $ echo 'let value = ()' > hidden/hidden.ml

  $ dune build ./main.exe 2> error
  [1]
  $ grep -F 'Library "hidden" not found' error
  Error: Library "hidden" not found.
