The stanza passes depext metadata to the shared package action expander.

  $ unset DUNE_SOURCE_ROOT DUNE_SOURCEROOT DUNE_PROJECT_ROOT
  $ cat >dune-project <<'EOF'
  > (lang dune 3.22)
  > (name foo)
  > (using unreleased 0.1)
  > (package (name foo))
  > EOF
  $ cat >dune <<'EOF'
  > (opam
  >  (package foo)
  >  (depexts missing-system-package)
  >  (build
  >   (run program-that-does-not-exist)))
  > EOF

  $ dune build .opam/foo/target
  File "dune", line 5, characters 7-34:
  5 |   (run program-that-does-not-exist)))
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: Program program-that-does-not-exist not found in the tree or in PATH
   (context: default)
  Hint: You may want to verify the following depexts are
  installed:
  missing-system-package
  [1]
