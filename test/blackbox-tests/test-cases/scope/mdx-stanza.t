An explicitly package-owned mdx stanza is removed from a scoped-out duplicate
package even when another package with the same name remains active.

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
  > (using mdx 0.5)
  > (package (name choice))
  > EOF
  $ cat > hidden/dune <<'EOF'
  > (scope
  >  (packages))
  > (mdx
  >  (package choice)
  >  (files doc.md)
  >  (preludes missing.ml))
  > EOF
  $ touch hidden/doc.md

  $ dune runtest
