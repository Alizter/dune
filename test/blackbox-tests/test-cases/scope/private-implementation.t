A scope filters package-owned interfaces, not unowned implementation stanzas.
Private libraries and executables in a scoped-out project remain buildable.

  $ cat > dune-project <<'EOF'
  > (lang dune 3.22)
  > (using unreleased 0.1)
  > (package (name hidden))
  > EOF
  $ cat > dune <<'EOF'
  > (scope
  >  (packages))
  > (library
  >  (name helper)
  >  (modules Helper))
  > (executable
  >  (name tool)
  >  (modules Tool)
  >  (libraries helper))
  > EOF
  $ echo 'let message = "private implementation"' > helper.ml
  $ echo 'let () = print_endline Helper.message' > tool.ml

  $ dune exec ./tool.exe
  private implementation
