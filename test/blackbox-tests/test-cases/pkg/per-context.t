Set lock file per context.

TODO: versioning will be added once this feature is stable

  $ cat >dune-workspace <<EOF
  > (lang dune 3.21)
  > (context
  >  (default
  >   (lock_dir foo.lock)))
  > (context
  >  (default
  >   (name foo)
  >   (lock_dir bar.lock)))
  > EOF

  $ mkdir foo.lock
  $ cat >foo.lock/lock.dune <<EOF
  > (lang package 0.1)
  > EOF
  $ cat >foo.lock/test.pkg <<EOF
  > (version 0.0.1)
  > (build
  >  (system "echo 'building from %{context_name}\nversion: %{pkg:test:version}'"))
  > EOF

  $ mkdir bar.lock
  $ cat >bar.lock/lock.dune <<EOF
  > (lang package 0.1)
  > EOF
  $ cat >bar.lock/test.pkg <<EOF
  > (version 0.0.2)
  > (build
  >  (system "echo 'building from %{context_name}\nversion: %{pkg:test:version}'"))
  > EOF

Build both contexts

  $ dune build @@_build/default/pkg-install
  building from default
  version: 0.0.1

  $ dune build @@_build/foo/pkg-install
  building from foo
  version: 0.0.2

The artifacts currently live under synthetic engine contexts rather than the
contexts that supply their compiler and environment.

  $ find _build -name cookie | sort
  _build/_default+lockfile/pkg/test/.opam/test/target/cookie
  _build/_foo+lockfile/pkg/test/.opam/test/target/cookie

Native lock packages must likewise keep separate artifacts for each real
context, without becoming part of the workspace's recursive test aliases.

  $ cat >dune-project <<'EOF'
  > (lang dune 3.24)
  > (package (name workspace) (allow_empty))
  > EOF
  $ echo '(dirs :standard \ native-source)' >dune
  $ mkdir native-source
  $ cat >native-source/dune-project <<'EOF'
  > (lang dune 3.24)
  > (package (name native))
  > EOF
  $ cat >native-source/dune <<'EOF'
  > (rule
  >  (target marker)
  >  (action (write-file %{target} %{context_name})))
  > (install (package native) (section share) (files marker))
  > (rule (alias runtest) (action (run false)))
  > EOF
  $ for lock in foo.lock bar.lock; do
  >   cat >"$lock/native.pkg" <<EOF
  > (version 1.0)
  > (source (copy $PWD/native-source))
  > EOF
  > done
  $ dune build @@_build/default/pkg-install @@_build/foo/pkg-install
  $ find _build -path '*/pkg/native/marker' | sort | while read marker; do
  >   printf '%s: %s\n' "$marker" "$(cat "$marker")"
  > done
  _build/_default+lockfile/pkg/native/marker: default
  _build/_foo+lockfile/pkg/native/marker: foo
  $ dune runtest

An ordinary workspace directory named pkg must not be taken over by the lock
package dispatcher. BUG: the old dispatch reserves it unnecessarily.

  $ mkdir pkg
  $ cat >pkg/dune <<'EOF'
  > (rule (target marker) (action (write-file %{target} workspace-pkg)))
  > EOF
  $ dune build pkg/marker
  Error: Don't know how to build pkg/marker
  [1]

Once .lockfile is the reserved build-only namespace, explicitly including a
workspace directory with that name must be rejected instead of mixing its
source files with lock package artifacts. Currently it is an ordinary source
directory and the build succeeds.

  $ mkdir .lockfile
  $ echo workspace-data >.lockfile/data
  $ echo '(dirs :standard .lockfile \ native-source)' >dune
  $ dune build .lockfile/data
