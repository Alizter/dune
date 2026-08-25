Mounted package preparation is invalidated when a watched lock entry changes. The
running Dune process fetches the replacement archive and rebuilds its consumer.

  $ cat > dune-workspace <<'EOF'
  > (lang dune 3.20)
  > (pkg enabled)
  > EOF
  $ cat > dune-project <<'EOF'
  > (lang dune 3.20)
  > (package
  >  (name main)
  >  (depends foo))
  > EOF
  $ cat > dune <<'EOF'
  > (executable
  >  (name main)
  >  (libraries foo))
  > EOF
  $ cat > main.ml <<'EOF'
  > let () = print_endline Foo.message
  > EOF

  $ mkdir foo
  $ cat > foo/dune-project <<'EOF'
  > (lang dune 3.20)
  > (package (name foo))
  > EOF
  $ cat > foo/dune <<'EOF'
  > (library
  >  (name foo)
  >  (public_name foo))
  > EOF
  $ echo 'let message = "first"' > foo/foo.ml
  $ tar cf foo-v1.tar foo
  $ rm -rf foo

  $ make_lockdir
  $ make_lockpkg foo <<EOF
  > (version 1.0)
  > (source
  >  (fetch
  >   (url file://$PWD/foo-v1.tar)
  >   (checksum md5=$(md5sum foo-v1.tar | cut -f1 -d' '))))
  > (build (run dune build @install))
  > EOF

  $ start_dune
  $ $timeout 10 dune rpc build --wait main.exe
  Success
  $ ./_build/default/main.exe
  first

Prepare the replacement archive before atomically publishing the changed lock
entry, then flush the file watcher and rebuild through the same server:

  $ mkdir foo
  $ cat > foo/dune-project <<'EOF'
  > (lang dune 3.20)
  > (package (name foo))
  > EOF
  $ cat > foo/dune <<'EOF'
  > (library
  >  (name foo)
  >  (public_name foo))
  > EOF
  $ echo 'let message = "second"' > foo/foo.ml
  $ tar cf foo-v2.tar foo
  $ rm -rf foo
  $ cat > dune.lock/foo.next <<EOF
  > (version 1.0)
  > (source
  >  (fetch
  >   (url file://$PWD/foo-v2.tar)
  >   (checksum md5=$(md5sum foo-v2.tar | cut -f1 -d' '))))
  > (build (run dune build @install))
  > EOF
  $ mv dune.lock/foo.next dune.lock/foo.pkg
  $ with_timeout dune rpc flush-file-watcher --wait
  $ $timeout 10 dune rpc build --wait main.exe
  Success
  $ ./_build/default/main.exe
  second
  $ test ! -d _build/_private/default/.pkg && echo no-old-package-rules
  no-old-package-rules
  $ stop_dune_quiet
