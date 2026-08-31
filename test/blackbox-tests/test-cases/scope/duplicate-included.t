Scope stanzas merged into the same logical directory remain duplicates.

  $ cat > dune-project <<'EOF'
  > (lang dune 3.22)
  > (using unreleased 0.1)
  > (package (name app))
  > EOF
  $ cat > dune <<'EOF'
  > (include scope.inc)
  > (scope
  >  (packages app))
  > EOF
  $ cat > scope.inc <<'EOF'
  > (scope
  >  (packages app))
  > EOF

  $ dune build 2> error
  [1]
  $ grep -F 'may not set the "scope" stanza more than once' error
  Error: may not set the "scope" stanza more than once
