A package name may appear only once in a scope's packages field.

  $ cat > dune-project <<'EOF'
  > (lang dune 3.22)
  > (using unreleased 0.1)
  > (package (name app))
  > EOF
  $ cat > dune <<'EOF'
  > (scope
  >  (packages app app))
  > EOF

  $ dune build 2> error
  [1]
  $ grep -F 'Package "app" is listed twice.' error
  Error: Package "app" is listed twice.
