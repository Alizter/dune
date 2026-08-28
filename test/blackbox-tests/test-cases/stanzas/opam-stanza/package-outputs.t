Libraries and binaries installed by an opam stanza become dynamic providers for
ordinary Dune rules without being declared in the stanza.

  $ unset DUNE_SOURCE_ROOT DUNE_SOURCEROOT DUNE_PROJECT_ROOT
  $ mkdir -p mock-opam-repository/packages producer consumer
  $ cat >mock-opam-repository/repo <<'EOF'
  > opam-version: "2.0"
  > EOF
  $ cat >dune-workspace <<EOF
  > (lang dune 3.24)
  > (pkg disabled)
  > (lock_dir
  >  (repositories mock))
  > (repository
  >  (name mock)
  >  (url "file://$PWD/mock-opam-repository"))
  > EOF
  $ cat >dune-project <<'EOF'
  > (lang dune 3.24)
  > (name test)
  > (using unreleased 0.1)
  > (package
  >  (name producer)
  >  (version 1.0)
  >  (dir producer))
  > (package
  >  (name consumer)
  >  (version 1.0)
  >  (dir consumer)
  >  (depends producer))
  > EOF

  $ cat >producer/provided.ml <<'EOF'
  > let message = "library from opam"
  > EOF
  $ cat >producer/tool.ml <<'EOF'
  > let () = print_endline "binary from opam"
  > EOF
  $ cat >producer/META <<'EOF'
  > version = "1.0"
  > archive(byte) = "provided.cma"
  > EOF
  $ echo 'installed file from opam' >producer/marker.txt
  $ cat >producer/dune <<'EOF'
  > (opam
  >  (package producer)
  >  (build
  >   (progn
  >    (run ocamlc -c provided.ml)
  >    (run ocamlc -a provided.cmo -o provided.cma)
  >    (run ocamlc -o provided-tool tool.ml)))
  >  (install
  >   (progn
  >    (run mkdir -p %{lib}/provided)
  >    (run cp META %{lib}/provided/META)
  >    (run cp provided.cmi %{lib}/provided/provided.cmi)
  >    (run cp provided.cma %{lib}/provided/provided.cma)
  >    (run cp provided-tool %{bin}/provided-tool)
  >    (run cp marker.txt %{share}/marker.txt))))
  > EOF

The consumer has no knowledge of the producer's output list. Library and binary
lookups force the producer's cookie and discover its installed artifacts.

  $ cat >consumer/main.ml <<'EOF'
  > let () = print_endline Provided.message
  > EOF
  $ cat >consumer/dune <<'EOF'
  > (executable
  >  (name main)
  >  (modes byte)
  >  (libraries provided))
  > (rule
  >  (target tool-output)
  >  (action
  >   (with-stdout-to %{target}
  >    (run %{bin:provided-tool}))))
  > (rule
  >  (target installed-output)
  >  (action
  >   (with-stdout-to %{target}
  >    (cat %{pkg:producer:share_root:marker.txt}))))
  > EOF

  $ dune build consumer/main.bc consumer/tool-output consumer/installed-output
  $ _build/default/consumer/main.bc
  library from opam
  $ cat _build/default/consumer/tool-output
  binary from opam
  $ cat _build/default/consumer/installed-output
  installed file from opam
