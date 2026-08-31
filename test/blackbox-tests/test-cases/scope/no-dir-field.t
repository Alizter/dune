A scope applies to its containing logical directory and has no dir field.

  $ cat > dune-project <<'EOF'
  > (lang dune 3.22)
  > (using unreleased 0.1)
  > (package (name app))
  > EOF
  $ cat > dune <<'EOF'
  > (scope
  >  (dir child)
  >  (packages app))
  > EOF

  $ dune build 2> error
  [1]
  $ grep -F 'Unknown field "dir"' error
  Error: Unknown field "dir"
