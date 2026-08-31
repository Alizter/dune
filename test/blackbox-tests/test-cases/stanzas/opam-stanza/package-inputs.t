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
