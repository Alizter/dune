Cookie-discovered capabilities are visible only across declared package edges.

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
  > (package (name producer) (dir producer))
  > (package (name consumer) (dir consumer) (allow_empty))
  > EOF

  $ cat >producer/provided.ml <<'EOF'
  > let message = "should not be visible"
  > EOF
  $ cat >producer/META <<'EOF'
  > version = "1.0"
  > archive(byte) = "provided.cma"
  > EOF
  $ cat >producer/provided-tool <<'EOF'
  > #!/bin/sh
  > echo should-not-run
  > EOF
  $ chmod +x producer/provided-tool
  $ echo should-not-be-readable >producer/marker.txt
  $ cat >producer/dune <<'EOF'
  > (opam
  >  (package producer)
  >  (exported_env
  >   (= HIDDEN_ENV hidden))
  >  (build
  >   (progn
  >    (run ocamlc -c provided.ml)
  >    (run ocamlc -a provided.cmo -o provided.cma)))
  >  (install
  >   (progn
  >    (run mkdir -p %{lib}/provided)
  >    (run cp META %{lib}/provided/META)
  >    (run cp provided.cmi %{lib}/provided/provided.cmi)
  >    (run cp provided.cma %{lib}/provided/provided.cma)
  >    (run cp provided-tool %{bin}/provided-tool)
  >    (run cp marker.txt %{share}/marker.txt))))
  > EOF

  $ cat >consumer/main.ml <<'EOF'
  > let () = print_endline Provided.message
  > EOF
  $ cat >consumer/dune <<'EOF'
  > (executable
  >  (name main)
  >  (modes byte)
  >  (libraries provided))
  > (rule
  >  (with-stdout-to binary-available
  >   (echo %{bin-available:provided-tool})))
  > (rule
  >  (target environment)
  >  (action
  >   (with-stdout-to %{target}
  >    (run sh -c "echo ${HIDDEN_ENV-unset}"))))
  > (rule
  >  (target installed-file)
  >  (action
  >   (with-stdout-to %{target}
  >    (cat %{pkg:producer:share_root:marker.txt}))))
  > EOF

  $ dune build consumer/binary-available consumer/environment
  $ cat _build/default/consumer/binary-available
  false
  $ cat _build/default/consumer/environment
  unset
  $ dune build consumer/installed-file
  File "consumer/dune", line 17, characters 8-45:
  17 |    (cat %{pkg:producer:share_root:marker.txt}))))
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: Package producer is not visible from this directory
  Hint: add a dependency on package "producer" to this package
  [1]
  $ dune build consumer/main.bc
  File "consumer/dune", line 4, characters 12-20:
  4 |  (libraries provided))
                  ^^^^^^^^
  Error: Library "provided" not found.
  -> required by _build/default/consumer/.main.eobjs/byte/dune__exe__Main.cmo
  -> required by _build/default/consumer/main.bc
  [1]
