A logical directory may contain only one scope stanza.

  $ cat > dune-project <<'EOF'
  > (lang dune 3.22)
  > (using unreleased 0.1)
  > (package (name app))
  > EOF
  $ cat > dune <<'EOF'
  > (scope
  >  (packages app))
  > (scope
  >  (packages app))
  > EOF

  $ dune build 2> error
  [1]
  $ grep -F 'Field "scope" is present too many times' error
  Error: Field "scope" is present too many times
