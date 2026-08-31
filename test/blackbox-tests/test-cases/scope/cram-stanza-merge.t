A scoped-out package-owned cram stanza contributes none of its configuration to
an unowned stanza that still applies to the same test.

  $ cat > dune-project <<'EOF'
  > (lang dune 3.22)
  > (using unreleased 0.1)
  > (package (name app))
  > EOF
  $ mkdir selected hidden
  $ cat > selected/dune-project <<'EOF'
  > (lang dune 3.22)
  > (using unreleased 0.1)
  > (package (name choice))
  > EOF
  $ cat > selected/dune <<'EOF'
  > (scope
  >  (packages choice))
  > EOF

  $ cat > hidden/dune-project <<'EOF'
  > (lang dune 3.22)
  > (using unreleased 0.1)
  > (cram enable)
  > (package (name choice))
  > EOF
  $ cat > hidden/dune <<'EOF'
  > (scope
  >  (packages))
  > (cram
  >  (package choice)
  >  (applies_to hidden.t)
  >  (setup_scripts missing.sh))
  > (cram
  >  (applies_to hidden.t))
  > EOF
  $ cat > hidden/hidden.t <<EOF
  >   \$ echo ran > $PWD/ran
  > EOF

  $ dune runtest
  $ cat ran
  ran
