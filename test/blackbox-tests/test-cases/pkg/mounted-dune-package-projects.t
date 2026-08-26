Lock packages that share one source archive are loaded once, while nested Dune
projects retain their own package identity and contribute libraries to the same
workspace build.

  $ export DUNE_CACHE_ROOT="$PWD/.cache"
  $ cat > dune-workspace <<'EOF'
  > (lang dune 3.20)
  > (pkg enabled)
  > EOF
  $ cat > dune-project <<'EOF'
  > (lang dune 3.20)
  > (package
  >  (name main)
  >  (depends foo bar))
  > EOF
  $ cat > dune <<'EOF'
  > (executable
  >  (name main)
  >  (libraries foo bar))
  > EOF
  $ cat > main.ml <<'EOF'
  > let () = Printf.printf "%s/%s\n" Foo.message Bar.message
  > EOF

  $ mkdir -p shared/sub shared/invalid.t
  $ cat > shared/dune-project <<'EOF'
  > (lang dune 3.20)
  > (package (name foo))
  > EOF
  $ cat > shared/dune <<'EOF'
  > (library
  >  (name foo)
  >  (public_name foo))
  > (cram
  >  (applies_to :whole_subtree))
  > EOF
  $ cat > shared/foo.ml <<'EOF'
  > let message = "root-project"
  > EOF

A Cram test directory may contain intentionally invalid Dune projects. It is test
data and must be masked before mounted project discovery attempts to decode it.

  $ cat > shared/invalid.t/dune-project <<'EOF'
  > (lang dune 3.20)
  > (lang dune 3.20)
  > EOF
  $ cat > shared/sub/dune-project <<'EOF'
  > (lang dune 3.20)
  > (package (name bar))
  > EOF
  $ cat > shared/sub/dune <<'EOF'
  > (library
  >  (name bar)
  >  (public_name bar))
  > EOF
  $ cat > shared/sub/bar.ml <<'EOF'
  > let message = "nested-project"
  > EOF
  $ tar cf shared.tar shared
  $ rm -rf shared

  $ checksum=$(md5sum shared.tar | cut -f1 -d' ')
  $ make_lockdir
  $ make_lockpkg foo <<EOF
  > (version 1.0)
  > (source
  >  (fetch
  >   (url file://$PWD/shared.tar)
  >   (checksum md5=$checksum)))
  > (build (run dune build @install))
  > EOF
  $ make_lockpkg bar <<EOF
  > (version 1.0)
  > (source
  >  (fetch
  >   (url file://$PWD/shared.tar)
  >   (checksum md5=$checksum)))
  > (build (run dune build @install))
  > EOF

  $ real_dune="$(command -v dune)"
  $ fake_bin="$TMPDIR/mounted-dune-package-projects-bin"
  $ rm -rf "$fake_bin"
  $ mkdir "$fake_bin"
  $ cat > "$fake_bin/dune" <<EOF
  > #!/bin/sh
  > echo nested-dune > "$PWD/nested-dune"
  > exit 99
  > EOF
  $ chmod +x "$fake_bin/dune"
  $ PATH="$fake_bin:$PATH" "$real_dune" build ./main.exe --display quiet
  $ ./_build/default/main.exe
  root-project/nested-project
  $ test ! -e nested-dune && echo no-nested-dune
  no-nested-dune
  $ test ! -d _build/_private/default/.pkg && echo no-old-package-rules
  no-old-package-rules

The shared transport has one immutable source snapshot and two lock identities
with distinct output roots. Package masking selects the relevant package from
each mounted view, while the nested library retains its project-relative output
directory.

  $ test "$(find "$DUNE_CACHE_ROOT/pkg-sources/v1" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 && echo one-source-snapshot
  one-source-snapshot
  $ test ! -e _build/_private/default/.pkg-source && echo no-directory-source-target
  no-directory-source-target
  $ test "$(find _build/_default+lockfile/pkg -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 2 && echo two-artifact-roots
  two-artifact-roots
  $ foo_root=$(echo _build/_default+lockfile/pkg/foo.1.0-*)
  $ bar_root=$(echo _build/_default+lockfile/pkg/bar.1.0-*)
  $ test -f "$foo_root/foo.cmxa" && test -f "$bar_root/sub/bar.cmxa" && echo nested-artifacts
  nested-artifacts
  $ test ! -e "$foo_root/sub/bar.cmxa" && test ! -e "$bar_root/foo.cmxa" && echo package-masks
  package-masks
