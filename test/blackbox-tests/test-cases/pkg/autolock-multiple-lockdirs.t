Multiple named contexts with different lock directories triggers an internal error.

This test documents a bug where using multiple named contexts with package
management causes an internal error about _private context.

  $ mkrepo

Make a library package:

  $ mkdir foo
  $ cat > foo/dune-project <<EOF
  > (lang dune 3.13)
  > (package (name foo))
  > EOF
  $ cat > foo/foo.ml <<EOF
  > let message = "Hello from foo!"
  > EOF
  $ cat > foo/dune <<EOF
  > (library
  >  (public_name foo))
  > EOF
  $ tar cf foo.tar foo
  $ rm -rf foo

  $ mkpkg foo <<EOF
  > build: [
  >   ["dune" "build" "-p" name "@install"]
  > ]
  > url {
  >  src: "$PWD/foo.tar"
  > }
  > EOF

  $ cat > dune-workspace <<EOF
  > (lang dune 3.22)
  > (pkg enabled)
  > (lock_dir
  >  (path dune.lock)
  >  (repositories mock))
  > (lock_dir
  >  (path dune.stable.lock)
  >  (repositories mock))
  > (lock_dir
  >  (path dune.latest.lock)
  >  (repositories mock))
  > (repository
  >  (name mock)
  >  (url "file://$PWD/mock-opam-repository"))
  > (context
  >  (default
  >   (name default)
  >   (lock_dir dune.lock)))
  > (context
  >  (default
  >   (name stable)
  >   (lock_dir dune.stable.lock)))
  > (context
  >  (default
  >   (name latest)
  >   (lock_dir dune.latest.lock)))
  > EOF

  $ cat > dune-project <<EOF
  > (lang dune 3.22)
  > (package
  >  (name myapp)
  >  (depends foo))
  > EOF

  $ cat > dune <<EOF
  > (rule
  >  (with-stdout-to myapp.ml
  >   (echo "let () = print_endline \"context: %{context_name}\"")))
  > (executable
  >  (name myapp)
  >  (libraries foo))
  > EOF

Autolocking with multiple contexts should work:

  $ dune exec --context=default ./myapp.exe
  context: default

  $ dune exec --context=stable ./myapp.exe
  context: stable

  $ dune exec --context=latest ./myapp.exe
  context: latest
