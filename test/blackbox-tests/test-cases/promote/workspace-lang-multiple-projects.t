Test that workspace lang controls promotion behavior across multiple projects with different dune-project versions

  $ cat >dune-workspace <<EOF
  > (lang dune 3.0)
  > EOF

  $ mkdir -p project1 project2

Create project1 with dune lang 3.0
  $ cat >project1/dune-project <<EOF
  > (lang dune 3.0)
  > EOF

  $ cat >project1/dune <<EOF
  > (rule
  >  (targets promoted1)
  >  (mode promote)
  >  (action (with-stdout-to promoted1 (echo "From project1"))))
  > EOF

Create project2 with dune lang 3.21
  $ cat >project2/dune-project <<EOF
  > (lang dune 3.21)
  > EOF

  $ cat >project2/dune <<EOF
  > (rule
  >  (targets promoted2)
  >  (mode promote)
  >  (action (with-stdout-to promoted2 (echo "From project2"))))
  > EOF

Build both projects
  $ dune build project1/promoted1 project2/promoted2

Both should be writable (644) because workspace lang is 3.0
  $ dune_cmd stat permissions project1/promoted1
  644
  $ dune_cmd stat permissions project2/promoted2
  644

Now test with workspace lang 3.21
  $ cat >dune-workspace <<EOF
  > (lang dune 3.21)
  > EOF

  $ rm -f project1/promoted1 project2/promoted2
  $ dune build project1/promoted1 project2/promoted2

Both should be read-only (444) because workspace lang is 3.21
  $ dune_cmd stat permissions project1/promoted1
  444
  $ dune_cmd stat permissions project2/promoted2
  444
