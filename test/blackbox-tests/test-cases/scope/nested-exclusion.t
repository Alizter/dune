A child scope can further restrict an enclosing scope. Package-owned stanzas are
filtered while unowned implementation stanzas remain available.

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
  >  (packages outer nested))
  > EOF
  $ cat > outer/inner/dune-project <<'EOF'
  > (lang dune 3.22)
  > (using unreleased 0.1)
  > (package (name nested))
  > EOF
  $ cat > outer/inner/dune <<'EOF'
  > (scope
  >  (packages))
  > (library
  >  (name nested)
  >  (public_name nested)
  >  (modules Nested))
  > (library
  >  (name helper)
  >  (modules Helper))
  > (executable
  >  (name tool)
  >  (modules Tool)
  >  (libraries helper))
  > EOF
  $ echo 'let value = ()' > outer/inner/nested.ml
  $ echo 'let message = "nested private implementation"' > outer/inner/helper.ml
  $ echo 'let () = print_endline Helper.message' > outer/inner/tool.ml

  $ dune exec ./outer/inner/tool.exe
  nested private implementation

  $ dune build ./main.exe 2> error
  [1]
  $ grep -F 'Library "nested" not found' error
  Error: Library "nested" not found.
