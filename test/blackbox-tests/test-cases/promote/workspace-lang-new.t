Test that promoted files are read-only with workspace lang >= 3.21

  $ cat > dune-workspace <<EOF
  > (lang dune 3.21)
  > EOF

  $ cat > dune-project <<EOF
  > (lang dune 3.0)
  > EOF

  $ cat > dune <<EOF
  > (rule
  >  (targets promoted)
  >  (mode promote)
  >  (action (with-stdout-to promoted (echo "Hello, world!"))))
  > EOF

  $ dune build promoted
  $ cat promoted
  Hello, world!

Promoted files should be read-only (444) with workspace lang 3.21, even if
project is 3.0.

  $ dune_cmd stat permissions promoted
  444

Verify that we need to chmod before editing

  $ chmod +w promoted
  $ echo "modified" > promoted
  $ dune build promoted
  $ cat promoted
  Hello, world!

After re-promotion, file should be read-only again

  $ dune_cmd stat permissions promoted
  444
