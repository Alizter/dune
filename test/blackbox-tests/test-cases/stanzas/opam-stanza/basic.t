An opam stanza executes its build and install actions and records the resulting
install layout in a cookie.

  $ unset DUNE_SOURCE_ROOT DUNE_SOURCEROOT DUNE_PROJECT_ROOT

  $ cat >dune-project <<'EOF'
  > (lang dune 3.22)
  > (name foo)
  > (version 1.0)
  > (using unreleased 0.1)
  > (package
  >  (name foo))
  > EOF
  $ cat >dune <<'EOF'
  > (opam
  >  (package foo)
  >  (build
  >   (system "echo 'built by the opam stanza' > built.txt"))
  >  (install
  >   (run cp built.txt %{bin}/foo)))
  > EOF

  $ dune build .opam/foo/target/cookie
  $ cat _build/default/.opam/foo/target/bin/foo
  built by the opam stanza
  $ test -f _build/default/.opam/foo/target/cookie
