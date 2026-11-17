Mounted packages can produce build artifacts, but must never register or apply
promotions. Promotion controls on the command line must not override this.

  $ make_lockdir
  $ cat > dune-project <<'EOF'
  > (lang dune 3.25)
  > (package (name main) (depends foo))
  > EOF
  $ mkdir _source
  $ cat > _source/dune-project <<'EOF'
  > (lang dune 3.25)
  > (package (name foo) (dir .))
  > EOF
  $ echo authored > _source/source.txt
  $ echo workspace > expected
  $ cat > _source/dune <<'EOF'
  > (rule
  >  (target source.txt)
  >  (mode promote)
  >  (action (write-file %{target} generated)))
  > (rule
  >  (target escaped.txt)
  >  (mode (promote (into ../../)))
  >  (action (write-file %{target} escaped)))
  > (rule
  >  (target checked)
  >  (action
  >   (progn
  >    (write-file missing.corrected corrected)
  >    (diff? missing missing.corrected)
  >    (write-file %{target} checked))))
  > (rule
  >  (target external-checked)
  >  (action
  >   (progn
  >    (write-file external.corrected corrected)
  >    (diff? ../../expected external.corrected)
  >    (write-file %{target} checked))))
  > EOF
  $ make_lockpkg foo <<EOF
  > (version 1.0)
  > (source (copy $PWD/_source))
  > (build (run false))
  > EOF

Rule promotion produces only build artifacts, leaving the original inputs
untouched.

  $ dune build _build/default/.pkg/foo/source.txt
  $ cat _build/default/.pkg/foo/source.txt
  generated
  $ cat _source/source.txt
  authored
  $ test ! -e _build/.to-delete-in-source-tree
  $ dune build --auto-promote _build/default/.pkg/foo/source.txt _build/default/.pkg/foo/escaped.txt
  $ cat _build/default/.pkg/foo/escaped.txt
  escaped
  $ test ! -e escaped.txt
  $ test ! -e .pkg

A missing diff operand is not permission to invent a workspace promotion path.

  $ dune build _build/default/.pkg/foo/checked > diff-output 2>&1
  [1]
  $ grep '^+corrected' diff-output
  +corrected
  $ dune promotion list

A mounted action cannot promote into the workspace either.

  $ dune build _build/default/.pkg/foo/external-checked > external-diff-output 2>&1
  [1]
  $ grep '^+corrected' external-diff-output
  +corrected
  $ dune promotion list

Neither manual nor automatic promotion can override these boundaries.

  $ dune promote
  $ dune build --auto-promote _build/default/.pkg/foo/checked > auto-diff-output 2>&1
  [1]
  $ grep '^+corrected' auto-diff-output
  +corrected
  $ dune build --auto-promote _build/default/.pkg/foo/external-checked > auto-external-output 2>&1
  [1]
  $ grep '^+corrected' auto-external-output
  +corrected
  $ dune promotion list
  $ test ! -e .pkg
  $ cat expected
  workspace

Naming the mounted file, or asking for its diff, finds nothing to promote.

  $ dune promote _build/default/.pkg/foo/missing
  Warning: Nothing to promote for _build/default/.pkg/foo/missing.
  $ dune promote .pkg/foo/missing
  Warning: Nothing to promote for .pkg/foo/missing.
  $ dune promotion diff
  $ test ! -e .pkg

Sandbox corrections and patch-back changes report failures without registering
promotions, including file deletion and creation.

  $ echo original > _source/check.txt
  $ cat >> _source/dune <<'EOF'
  > (rule
  >  (target corrected-ok)
  >  (corrections produce)
  >  (deps check.txt)
  >  (action
  >   (progn
  >    (system "echo corrected > check.txt.corrected")
  >    (write-file %{target} done))))
  > (rule
  >  (target patched-ok)
  >  (deps check.txt (sandbox patch_back_source_tree))
  >  (action
  >   (progn
  >    (system "rm check.txt; echo fresh > new-file")
  >    (write-file %{target} done))))
  > EOF
  $ dune build --auto-promote _build/default/.pkg/foo/corrected-ok > correction-output 2>&1
  [1]
  $ grep '^+corrected' correction-output
  +corrected
  $ dune promotion list
  $ dune build --auto-promote _build/default/.pkg/foo/patched-ok > patch-back-output 2>&1
  [1]
  $ grep -q 'should be deleted' patch-back-output
  $ grep -q 'new-file' patch-back-output
  $ grep -q '^+fresh' patch-back-output
  $ dune promotion list
  $ test ! -e .pkg

An alias-only action in the mount has no target to request, but its failing
diff must still be reported without registering or applying a promotion.

  $ echo authored > _source/alias-expected
  $ cat >> _source/dune <<'EOF'
  > (rule
  >  (alias mounted-check)
  >  (action
  >   (progn
  >    (write-file alias-expected.corrected corrected)
  >    (diff? alias-expected alias-expected.corrected))))
  > EOF
  $ dune build @_build/default/.pkg/foo/mounted-check > alias-output 2>&1
  [1]
  $ grep '^+corrected' alias-output
  +corrected
  $ dune promotion list
  $ dune promote
  $ dune build --auto-promote @_build/default/.pkg/foo/mounted-check > auto-alias-output 2>&1
  [1]
  $ grep '^+corrected' auto-alias-output
  +corrected
  $ dune promotion list
  $ test ! -e .pkg

Cram tests of a mounted package are never run, whether requested through the
mount or through the workspace.

  $ cat > _source/mounted.t <<EOF
  >   $ echo ran > $PWD/cram-ran
  > EOF
  $ dune build _build/default/.pkg/foo/mounted.t
  $ grep -c cram-ran _build/default/.pkg/foo/mounted.t
  1
  $ dune build @_build/default/.pkg/foo/runtest
  $ dune build @_build/default/.pkg/foo/mounted
  Error: Alias "mounted" specified on the command line is empty.
  It is not defined in .pkg/foo or any of its descendants.
  [1]
  $ dune build @runtest
  $ test ! -e cram-ran

Ordinary workspace promotion remains available.

  $ cat > dune <<'EOF'
  > (rule
  >  (alias correct)
  >  (action
  >   (progn
  >    (write-file expected.corrected corrected)
  >    (diff? expected expected.corrected))))
  > EOF
  $ dune build @correct > ordinary-output 2>&1
  [1]
  $ dune promotion list
  expected
  $ dune promote
  Promoting _build/default/expected.corrected to expected.
  $ cat expected
  corrected

A workspace rule in promote mode can copy a mounted target; the promotion
lands in the workspace.

  $ cat > dune <<'EOF'
  > (rule
  >  (target from-mount.txt)
  >  (mode promote)
  >  (action (copy .pkg/foo/source.txt %{target})))
  > EOF
  $ dune build from-mount.txt
  $ cat from-mount.txt
  generated
  $ test ! -e .pkg

Anonymous actions used for inferred interfaces report mismatches without
registering promotions, whether the interface is missing or outdated.

  $ mkdir _source/inferred
  $ cat > _source/inferred/dune <<'EOF'
  > (library (name foo))
  > EOF
  $ echo 'let value = 42' > _source/inferred/foo.ml
  $ dune ocaml inferred-mli .pkg/foo/inferred/foo.ml > inferred-output 2>&1
  [1]
  $ grep '^+val' inferred-output
  +val value : int
  $ dune promotion list
  $ dune promote
  $ test ! -e .pkg
  $ dune ocaml inferred-mli --auto-promote .pkg/foo/inferred/foo.ml > auto-inferred-output 2>&1
  [1]
  $ grep '^+val' auto-inferred-output
  +val value : int
  $ dune promotion list
  $ test ! -e .pkg

  $ echo 'val value : string' > _source/inferred/foo.mli
  $ dune ocaml inferred-mli .pkg/foo/inferred/foo.ml > outdated-output 2>&1
  [1]
  $ grep '^[-+]val' outdated-output
  -val value : string
  +val value : int
  $ dune promotion list
  $ dune promote
  $ dune ocaml inferred-mli --auto-promote .pkg/foo/inferred/foo.ml > auto-outdated-output 2>&1
  [1]
  $ grep '^[-+]val' auto-outdated-output
  -val value : string
  +val value : int
  $ dune promotion list
  $ test ! -e .pkg
  $ cat _source/inferred/foo.mli
  val value : string

The invariant is not tied to a context named default.

  $ cat > dune-workspace <<'EOF'
  > (lang dune 3.25)
  > (pkg enabled)
  > (context (default (name host)))
  > (context (default (name target) (host host)))
  > EOF
  $ dune build --auto-promote _build/target/.pkg/foo/source.txt
  $ cat _build/target/.pkg/foo/source.txt
  generated
  $ dune build --auto-promote _build/host/.pkg/foo/checked > host-output 2>&1
  [1]
  $ grep '^+corrected' host-output
  +corrected
  $ dune promotion list
  $ dune promote
  $ test ! -e .pkg
