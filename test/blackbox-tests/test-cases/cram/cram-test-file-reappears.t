Soundness bug: dune's workspace-local rule cache only consults an
in-memory digest table for target existence (rule_cache.ml
compute_target_digests); it never stats the file on disk. If a target
in _build is missing but its digest entry survives, dune returns a
stale cache hit. A downstream consumer that is independently
invalidated then fails sandbox setup trying to copy the missing target.

This is a simulated repro of a state we observed in the wild: after a
sequence of jj operations, dune runtest failed with cram.sh: No such
file or directory even though the .t source was unchanged.

  $ make_dune_project 3.20

  $ cat >setup_script <<'EOF'
  > #!/bin/sh
  > true
  > EOF

  $ chmod +x setup_script

  $ cat >dune <<EOF
  > (cram
  >  (applies_to :whole_subtree)
  >  (deps setup_script))
  > EOF

  $ cat >foo.t <<'EOF'
  >   $ echo hello
  >   hello
  > EOF

  $ dune build @runtest

Out-of-band removal of cram.sh leaves the digest table intact.

  $ rm _build/default/.cram.foo.t/cram.sh
  rm: cannot remove '_build/default/.cram.foo.t/cram.sh': No such file or directory
  [1]

Touching setup_script invalidates the run action but not make_script.
Dune treats cram.sh as a cache hit and the run action fires with
cram.sh missing.

  $ echo "# touch" >> setup_script

  $ dune build @runtest 2>&1 | censor
  
