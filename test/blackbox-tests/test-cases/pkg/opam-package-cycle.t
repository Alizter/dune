Testing how the solver handles cycles in an opam repository.

  $ . ./helpers.sh
  $ mkrepo

  $ mkpkg a <<'EOF'
  > depends: [ "b" ]
  > EOF
  $ mkpkg b <<'EOF'
  > depends: [ "c" ]
  > EOF
  $ mkpkg c <<'EOF'
  > depends: [ "a" ]
  > EOF

Solver doesn't complain about cycles.

  $ solve a
  Error: Dependency cycle between packages:
     a.0.0.1
  -> b.0.0.1
  -> c.0.0.1
  -> a.0.0.1
  -> required by lock directory environment for context "default"
  -> required by base environment for context "default"
  -> required by loading findlib for context "default"
  -> required by loading the OCaml compiler for context "default"
  [1]
  $ solve b
  Error: Dependency cycle between packages:
     a.0.0.1
  -> b.0.0.1
  -> c.0.0.1
  -> a.0.0.1
  -> required by lock directory environment for context "default"
  -> required by base environment for context "default"
  -> required by loading findlib for context "default"
  -> required by loading the OCaml compiler for context "default"
  [1]
  $ solve c
  Error: Dependency cycle between packages:
     a.0.0.1
  -> b.0.0.1
  -> c.0.0.1
  -> a.0.0.1
  -> required by lock directory environment for context "default"
  -> required by base environment for context "default"
  -> required by loading findlib for context "default"
  -> required by loading the OCaml compiler for context "default"
  [1]
