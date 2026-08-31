Project-level package rules use the scope-filtered package set.

  $ cat > dune-project <<'EOF'
  > (lang dune 3.22)
  > (using unreleased 0.1)
  > (generate_opam_files true)
  > (package
  >  (name visible)
  >  (dir visible)
  >  (allow_empty))
  > (package
  >  (name hidden)
  >  (dir hidden)
  >  (allow_empty))
  > EOF
  $ mkdir visible hidden
  $ cat > visible/dune <<'EOF'
  > (scope
  >  (packages visible))
  > EOF
  $ cat > hidden/dune <<'EOF'
  > (scope
  >  (packages))
  > EOF

  $ dune build visible.opam
  $ test -e visible.opam && echo visible-opam
  visible-opam

  $ dune build hidden.opam
  Error: Don't know how to build hidden.opam
  [1]
