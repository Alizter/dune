Auto-locking publishes its generated lock before mounted projects are loaded, so
the first build can fetch, load, and compile a Dune package in one invocation.

  $ mkrepo
  $ add_mock_repo_if_needed
  $ enable_pkg

  $ mkdir autofoo
  $ cat > autofoo/dune-project <<'EOF'
  > (lang dune 3.13)
  > (package (name autofoo))
  > EOF
  $ cat > autofoo/dune <<'EOF'
  > (library
  >  (name autofoo)
  >  (public_name autofoo))
  > EOF
  $ cat > autofoo/autofoo.ml <<'EOF'
  > let message = "mounted autolock"
  > EOF
  $ tar cf autofoo.tar autofoo
  $ rm -rf autofoo

  $ mkpkg autofoo <<EOF
  > build: [
  >   ["dune" "build" "@install"]
  > ]
  > url {
  >  src: "$PWD/autofoo.tar"
  > }
  > EOF

  $ cat > dune-project <<'EOF'
  > (lang dune 3.21)
  > (package
  >  (name main)
  >  (depends autofoo))
  > EOF
  $ cat > dune <<'EOF'
  > (executable
  >  (name main)
  >  (libraries autofoo))
  > EOF
  $ cat > main.ml <<'EOF'
  > let () = print_endline Autofoo.message
  > EOF

A failing `dune` first in `PATH` proves that the generated package action is not
executed by a nested Dune process.

  $ real_dune="$(command -v dune)"
  $ fake_bin="$TMPDIR/mounted-dune-package-autolock-bin"
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
  mounted autolock
  $ mounted_root=$(echo _build/_default+lockfile/pkg/autofoo.0.0.1-*)
  $ test -f "$mounted_root/autofoo.cmxa" && echo mounted-first-build
  mounted-first-build
  $ test ! -e nested-dune && echo no-nested-dune
  no-nested-dune
  $ test ! -d _build/_private/default/.pkg && echo no-old-package-rules
  no-old-package-rules
  $ test ! -e dune.lock && echo generated-lock-is-internal
  generated-lock-is-internal
