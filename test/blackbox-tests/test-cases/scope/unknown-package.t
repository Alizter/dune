Explicit package names must refer to packages defined beneath the scope.

  $ cat > dune-project <<'EOF'
  > (lang dune 3.22)
  > (using unreleased 0.1)
  > (package (name app))
  > EOF
  $ mkdir child
  $ cat > child/dune <<'EOF'
  > (scope
  >  (packages missing))
  > EOF

  $ dune build 2> error
  [1]
  $ grep -F "The following packages are not defined beneath this scope: missing" error
  Error: The following packages are not defined beneath this scope: missing
