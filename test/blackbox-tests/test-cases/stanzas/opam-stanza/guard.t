The opam stanza is guarded by the unreleased extension.

  $ unset DUNE_SOURCE_ROOT DUNE_SOURCEROOT DUNE_PROJECT_ROOT

  $ cat >dune-project <<'EOF'
  > (lang dune 3.22)
  > (name foo)
  > (version 1.0)
  > (package
  >  (name foo))
  > EOF
  $ cat >dune <<'EOF'
  > (opam
  >  (package foo))
  > EOF

  $ dune build @all
  File "dune", lines 1-2, characters 0-21:
  1 | (opam
  2 |  (package foo))
  Error: 'opam' is available only when unreleased is enabled in the
  dune-project or workspace file. You must enable it using (using unreleased
  0.1) in the file.
  Note however that unreleased is experimental and might change without notice
  in the future.
  [1]

Enabling the extension will make the stanza available.

  $ cat >>dune-project <<'EOF'
  > (using unreleased 0.1)
  > EOF
  $ dune build @all
