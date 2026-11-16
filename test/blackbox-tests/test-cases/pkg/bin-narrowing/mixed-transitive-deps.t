A "mixed" dependency chain [p] -> [q] -> [r] has one edge crossing the
workspace/lockdir boundary. Only the packages listed in a package's
[(depends ...)] are searched for binaries, so a package whose binaries are
needed must be declared explicitly.

[p] (workspace) -> [q] (workspace) -> [r] (lockdir). [p] only lists [q], so
[r-tool] does not resolve from [p]'s stanza.

  $ make_lockdir

A lockdir package [r] that installs [r-tool]:

  $ make_lockpkg r <<'EOF'
  > (version 0.0.1)
  > (build
  >  (progn
  >   (system "echo '#!/bin/sh' > r-tool")
  >   (system "echo 'echo from r' >> r-tool")
  >   (system "chmod +x r-tool")
  >   (system "echo 'bin: [ \"r-tool\" ]' > r.install")))
  > EOF

  $ mkdir -p p q
  $ cat >p/dune <<'EOF'
  > (rule (with-stdout-to r-avail (echo %{bin-available:r-tool})))
  > EOF

  $ make_dune_project 3.25
  $ cat >> dune-project <<'EOF'
  > (package (name p) (allow_empty) (dir p) (depends q))
  > (package (name q) (allow_empty) (dir q) (depends r))
  > EOF

  $ dune build p/r-avail

[r] is visible through the workspace package [q]:

  $ cat _build/default/p/r-avail
  true

Declaring [r] directly on [p] makes it visible:

  $ make_dune_project 3.25
  $ cat >> dune-project <<'EOF'
  > (package (name p) (allow_empty) (dir p) (depends q r))
  > (package (name q) (allow_empty) (dir q) (depends r))
  > EOF
  $ dune clean
  $ dune build p/r-avail
  $ cat _build/default/p/r-avail
  true

Both blocks print [true]: [p] sees the dependencies of the packages it lists,
whether it reaches [r] through [q] or lists it directly.

[p] (workspace) -> [q] (lockdir) -> [r] (workspace) is valid too. The opaque
recipe for [q] receives [r], and [r-tool] is in the dependency closure of [p].

  $ rm -rf p q r dune.lock
  $ dune clean

  $ make_lockdir
  $ make_lockpkg q <<'EOF'
  > (version 0.0.1)
  > (depends r)
  > (build (system "true"))
  > EOF

  $ mkdir -p p r
  $ cat >r/r-tool.sh <<'EOF'
  > #!/bin/sh
  > echo from r
  > EOF
  $ chmod +x r/r-tool.sh
  $ cat >r/dune <<'EOF'
  > (install (package r) (section bin) (files (r-tool.sh as r-tool)))
  > EOF
  $ cat >p/dune <<'EOF'
  > (rule (with-stdout-to r-avail (echo %{bin-available:r-tool})))
  > EOF

  $ make_dune_project 3.25
  $ cat >> dune-project <<'EOF'
  > (package (name p) (allow_empty) (dir p) (depends q))
  > (package (name r) (allow_empty) (dir r))
  > EOF

  $ dune build p/r-avail
  $ cat _build/default/p/r-avail
  true
