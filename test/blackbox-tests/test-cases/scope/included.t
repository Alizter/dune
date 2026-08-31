A scope supplied by a statically included dune file is applied to its containing
directory.

  $ cat > dune-project <<'EOF'
  > (lang dune 3.22)
  > (using unreleased 0.1)
  > (package (name app))
  > EOF
  $ cat > dune <<'EOF'
  > (executable
  >  (name main)
  >  (libraries included))
  > EOF
  $ echo 'let () = ()' > main.ml

  $ mkdir included
  $ cat > included/dune-project <<'EOF'
  > (lang dune 3.22)
  > (using unreleased 0.1)
  > (package (name included))
  > EOF
  $ cat > included/dune <<'EOF'
  > (include scope.inc)
  > (library
  >  (name included)
  >  (public_name included))
  > EOF
  $ cat > included/scope.inc <<'EOF'
  > (scope
  >  (packages))
  > EOF
  $ echo 'let value = ()' > included/included.ml

  $ dune build ./main.exe 2> error
  [1]
  $ grep -F 'Library "included" not found' error
  Error: Library "included" not found.
