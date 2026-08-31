The scope stanza is guarded by the unreleased language extension.

  $ cat > dune-project <<'EOF'
  > (lang dune 3.22)
  > (package (name guard))
  > EOF
  $ cat > dune <<'EOF'
  > (scope
  >  (packages guard))
  > EOF

  $ dune build 2> error
  [1]
  $ grep -F "Error: 'scope' is available only when unreleased is enabled" error
  Error: 'scope' is available only when unreleased is enabled in the
