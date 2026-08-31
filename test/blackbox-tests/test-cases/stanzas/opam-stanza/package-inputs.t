An opam stanza receives the dynamically discovered files, binaries, and
variables of its exact package dependencies.

  $ unset DUNE_SOURCE_ROOT DUNE_SOURCEROOT DUNE_PROJECT_ROOT

  $ mkdir producer consumer
  $ cat >dune-project <<'EOF'
  > (lang dune 3.22)
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

The producer declares no libraries, binaries, or variables statically. Its
install action and cookie are the only descriptions of those outputs.

  $ cat >producer/dune <<'EOF'
  > (opam
  >  (package producer)
  >  (install
  >   (progn
  >    (run mkdir -p %{lib}/producer)
  >    (run cp marker.txt %{lib}/producer/marker.txt)
  >    (run cp producer-tool %{bin}/producer-tool))))
  > EOF
  $ echo 'library from producer' >producer/marker.txt
  $ cat >producer/producer-tool <<'EOF'
  > #!/bin/sh
  > echo 'binary from producer'
  > EOF
  $ chmod +x producer/producer-tool
  $ cat >producer/producer.config <<'EOF'
  > opam-version: "2.0"
  > variables {
  >   message: "variable from producer"
  > }
  > EOF

The consumer names only the package edge. Its recipe uses all three dynamically
loaded capabilities and installs the observations as its own package outputs.

  $ cat >consumer/dune <<'EOF'
  > (opam
  >  (package consumer)
  >  (build
  >   (progn
  >    (system "producer-tool > bin.txt")
  >    (system "cat %{pkg:producer:lib}/marker.txt > lib.txt")
  >    (system "echo %{pkg:producer:message} > variable.txt")))
  >  (install
  >   (progn
  >    (run mkdir -p %{share}/consumer)
  >    (run cp bin.txt %{share}/consumer/bin.txt)
  >    (run cp lib.txt %{share}/consumer/lib.txt)
  >    (run cp variable.txt %{share}/consumer/variable.txt))))
  > EOF

  $ dune build @all
  $ consumer_share=_build/default/consumer/.opam/consumer/target/share/consumer
  $ cat "$consumer_share/bin.txt"
  binary from producer
  $ cat "$consumer_share/lib.txt"
  library from producer
  $ cat "$consumer_share/variable.txt"
  variable from producer

An Opam recipe can consume the same capabilities from any package provider in
[Package_db], rather than requiring another user-authored Opam stanza.

  $ mkdir lock-provider
  $ cd lock-provider
  $ mkdir consumer
  $ cat >dune-workspace <<'EOF'
  > (lang dune 3.22)
  > (pkg enabled)
  > EOF
  $ cat >dune-project <<'EOF'
  > (lang dune 3.22)
  > (name consumer)
  > (using unreleased 0.1)
  > (package
  >  (name consumer)
  >  (dir consumer)
  >  (depends locked))
  > EOF
  $ mkdir dune.lock
  $ cat >dune.lock/lock.dune <<'EOF'
  > (lang package 0.1)
  > EOF
  $ cat >dune.lock/locked.pkg <<'EOF'
  > (version 2.0)
  > (build
  >  (write-file marker.txt "file from lock\n"))
  > (install
  >  (progn
  >   (run mkdir -p %{share}/locked)
  >   (run cp marker.txt %{share}/locked/marker.txt)))
  > EOF

  $ cat >consumer/dune <<'EOF'
  > (opam
  >  (package consumer)
  >  (build
  >   (progn
  >    (system "cat %{pkg:locked:share}/marker.txt > result.txt")
  >    (system "echo %{pkg:locked:version} >> result.txt")))
  >  (install
  >   (run cp result.txt %{share}/result.txt)))
  > EOF

  $ dune build consumer/.opam/consumer/target
  File "consumer/dune", lines 1-8, characters 0-220:
  1 | (opam
  2 |  (package consumer)
  3 |  (build
  4 |   (progn
  5 |    (system "cat %{pkg:locked:share}/marker.txt > result.txt")
  6 |    (system "echo %{pkg:locked:version} >> result.txt")))
  7 |  (install
  8 |   (run cp result.txt %{share}/result.txt)))
  Error: Package locked is not provided by an opam stanza
  [1]
