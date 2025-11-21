Test that promoted files are writable with workspace lang < 3.21

  $ cat > dune-workspace <<EOF
  > (lang dune 3.0)
  > EOF

  $ cat > dune-project <<EOF
  > (lang dune 3.21)
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

Promoted files should be writable (644) with workspace lang 3.0, even if
project is 3.21

  $ dune_cmd stat permissions promoted
  644
