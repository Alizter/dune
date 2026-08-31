Workspace-installed binaries (the local_bins in [Artifacts]) are narrowed to a
package and its immediate dependencies.

Three workspace packages form a chain [p] -> [q] -> [r]. [q] installs [q-tool]
and [r] installs [r-tool]. A sibling [s] installs [s-tool].

  $ mkdir -p p q r s
  $ cat >q/q-tool.sh <<'EOF'
  > #!/bin/sh
  > echo from q
  > EOF
  $ cat >r/r-tool.sh <<'EOF'
  > #!/bin/sh
  > echo from r
  > EOF
  $ cat >s/s-tool.sh <<'EOF'
  > #!/bin/sh
  > echo from s
  > EOF
  $ chmod +x q/q-tool.sh r/r-tool.sh s/s-tool.sh
  $ cat >q/dune <<'EOF'
  > (install (package q) (section bin) (files (q-tool.sh as q-tool)))
  > EOF
  $ cat >r/dune <<'EOF'
  > (install (package r) (section bin) (files (r-tool.sh as r-tool)))
  > EOF
  $ cat >s/dune <<'EOF'
  > (install (package s) (section bin) (files (s-tool.sh as s-tool)))
  > EOF
  $ cat >p/dune <<'EOF'
  > (rule (with-stdout-to q-avail (echo %{bin-available:q-tool})))
  > (rule (with-stdout-to r-avail (echo %{bin-available:r-tool})))
  > (rule (with-stdout-to s-avail (echo %{bin-available:s-tool})))
  > EOF

  $ make_dune_project 3.25
  $ cat >> dune-project <<'EOF'
  > (package (name p) (allow_empty) (dir p) (depends q))
  > (package (name q) (allow_empty) (dir q) (depends r))
  > (package (name r) (allow_empty) (dir r))
  > (package (name s) (allow_empty) (dir s))
  > EOF

  $ dune build @all
[q-tool] (direct dep p -> q) is available:

  $ cat _build/default/p/q-avail
  true

[r-tool] (transitive dep p -> q -> r) is not implicitly available:

  $ cat _build/default/p/r-avail
  false

[s-tool] (an undeclared sibling) is also not available:

  $ cat _build/default/p/s-avail
  false
