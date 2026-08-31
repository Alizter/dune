Scope selection is applied before --only-packages. A scoped-out package is not
a candidate for command-line package selection.

  $ cat > dune-project <<'EOF'
  > (lang dune 3.22)
  > (using unreleased 0.1)
  > (package
  >  (name visible)
  >  (dir visible))
  > (package
  >  (name hidden)
  >  (dir hidden))
  > EOF
  $ mkdir visible hidden
  $ cat > visible/dune <<'EOF'
  > (scope
  >  (packages visible))
  > (library
  >  (name visible)
  >  (public_name visible))
  > EOF
  $ echo 'let value = ()' > visible/visible.ml
  $ cat > hidden/dune <<'EOF'
  > (scope
  >  (packages))
  > (library
  >  (name hidden)
  >  (public_name hidden))
  > EOF
  $ echo 'let value = ()' > hidden/hidden.ml

  $ dune build --only-packages hidden 2> error
  [1]
  $ grep -F "I don't know about package hidden" error
  Error: I don't know about package hidden (passed through --only-packages)

  $ dune build --only-packages visible @install
