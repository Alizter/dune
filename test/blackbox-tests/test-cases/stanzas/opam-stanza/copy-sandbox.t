Opam actions run against a writable copy and cannot mutate their source.

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
  >   (run cp replacement.txt input.txt))
  >  (install
  >   (progn
  >    (run mkdir -p %{share}/foo)
  >    (run cp input.txt %{share}/foo/result.txt))))
  > EOF
  $ echo original >input.txt
  $ echo replacement >replacement.txt

  $ dune build @all
  $ cat input.txt
  original
  $ cat _build/default/.opam/foo/target/share/foo/result.txt
  replacement
