Opam stanzas compose over the exact transitive package closure. Undeclared
siblings do not contribute binaries, variables, environments, or targets.

  $ unset DUNE_SOURCE_ROOT DUNE_SOURCEROOT DUNE_PROJECT_ROOT
  $ mkdir leaf middle top other
  $ cat >dune-project <<'EOF'
  > (lang dune 3.24)
  > (name test)
  > (using unreleased 0.1)
  > (package (name leaf) (dir leaf))
  > (package (name middle) (dir middle) (depends leaf))
  > (package (name top) (dir top) (depends middle))
  > (package (name other) (dir other))
  > EOF

  $ cat >leaf/leaf-tool <<'EOF'
  > #!/bin/sh
  > echo leaf-binary
  > EOF
  $ chmod +x leaf/leaf-tool
  $ cat >leaf/leaf.config <<'EOF'
  > opam-version: "2.0"
  > variables { message: "leaf-variable" }
  > EOF
  $ cat >leaf/dune <<'EOF'
  > (opam
  >  (package leaf)
  >  (exported_env
  >   (= LEAF_ENV leaf-environment))
  >  (install
  >   (run cp leaf-tool %{bin}/leaf-tool)))
  > EOF

  $ cat >middle/dune <<'EOF'
  > (opam
  >  (package middle)
  >  (depends leaf)
  >  (exported_env
  >   (= MIDDLE_ENV middle-environment)))
  > EOF

  $ cat >other/other-tool <<'EOF'
  > #!/bin/sh
  > echo unrelated
  > EOF
  $ chmod +x other/other-tool
  $ cat >other/dune <<'EOF'
  > (opam
  >  (package other)
  >  (install
  >   (run cp other-tool %{bin}/other-tool)))
  > EOF

  $ cat >top/dune <<'EOF'
  > (opam
  >  (package top)
  >  (depends middle)
  >  (build
  >   (progn
  >    (system "leaf-tool > result.txt")
  >    (system "echo %{pkg:leaf:message} >> result.txt")
  >    (system "echo $LEAF_ENV >> result.txt")
  >    (system "echo $MIDDLE_ENV >> result.txt")
  >    (system "if command -v other-tool >/dev/null; then exit 1; fi")))
  >  (install
  >   (run cp result.txt %{share}/result.txt)))
  > EOF

  $ dune build top/.opam/top/target
  $ cat _build/default/top/.opam/top/target/share/result.txt
  leaf-binary
  leaf-variable
  leaf-environment
  middle-environment
  $ test ! -e _build/default/other/.opam/other/target
