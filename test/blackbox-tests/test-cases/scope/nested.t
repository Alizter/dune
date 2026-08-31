Nested scopes intersect: an inner scope cannot re-enable a package excluded by
an enclosing scope.

  $ cat > dune-project <<'EOF'
  > (lang dune 3.22)
  > (using unreleased 0.1)
  > (package (name app))
  > EOF
  $ cat > dune <<'EOF'
  > (executable
  >  (name main)
  >  (libraries nested))
  > EOF
  $ echo 'let () = ()' > main.ml

  $ mkdir -p outer/inner
  $ cat > outer/dune-project <<'EOF'
  > (lang dune 3.22)
  > (using unreleased 0.1)
  > (package (name outer))
  > EOF
  $ cat > outer/dune <<'EOF'
  > (scope
  >  (packages outer))
  > (subdir inner
  >  (scope
  >   (packages nested)))
  > EOF
  $ cat > outer/inner/dune-project <<'EOF'
  > (lang dune 3.22)
  > (package (name nested))
  > EOF
  $ cat > outer/inner/dune <<'EOF'
  > (library
  >  (name nested)
  >  (public_name nested))
  > EOF
  $ echo 'let value = ()' > outer/inner/nested.ml

  $ dune build ./main.exe 2> error
  [1]
  $ grep -F 'Library "nested" not found' error
  Error: Library "nested" not found.
