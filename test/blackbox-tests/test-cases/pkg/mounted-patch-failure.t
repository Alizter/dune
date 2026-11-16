A patch that does not apply to a mounted package's source fails the build of
anything that needs the package. The error is located at the patch action in
the build copy of the lock file.

  $ make_lockdir
  $ cat > dune-project <<'EOF'
  > (lang dune 3.25)
  > (package (name main) (dir .) (depends foo))
  > EOF
  $ echo '(executable (name main) (libraries foo))' > dune
  $ echo 'let () = print_endline Foo.message' > main.ml
  $ mkdir _source
  $ cat > _source/dune-project <<'EOF'
  > (lang dune 3.25)
  > (package (name foo))
  > EOF
  $ echo '(library (public_name foo))' > _source/dune
  $ echo 'let message = "original"' > _source/foo.ml
  $ make_lockpkg foo <<EOF
  > (version 1.0)
  > (source (copy $PWD/_source))
  > (build
  >  (progn
  >   (patch stale.patch)
  >   (run false)))
  > EOF
  $ make_lockpkg_file foo stale.patch <<'EOF'
  > --- a/foo.ml
  > +++ b/foo.ml
  > @@ -1 +1 @@
  > -let message = "something else"
  > +let message = "patched"
  > EOF

  $ dune build main.exe
  File "dune.lock/foo.pkg", line 5, characters 9-20:
  5 |   (patch stale.patch)
               ^^^^^^^^^^^
  Error: Patch could not be applied to "foo.ml": hunk does not match file
  contents
  [1]

The source is left as it was.

  $ cat _source/foo.ml
  let message = "original"

A patch for a file that does not exist fails in the same way.

  $ make_lockpkg_file foo stale.patch <<'EOF'
  > --- a/absent.ml
  > +++ b/absent.ml
  > @@ -1 +1 @@
  > -let message = "original"
  > +let message = "patched"
  > EOF
  $ dune build main.exe
  File "dune.lock/foo.pkg", line 5, characters 9-20:
  5 |   (patch stale.patch)
               ^^^^^^^^^^^
  Error: Cannot edit file "absent.ml": file does not exist
  [1]

Fixing the patch recovers the build.

  $ make_lockpkg_file foo stale.patch <<'EOF'
  > --- a/foo.ml
  > +++ b/foo.ml
  > @@ -1 +1 @@
  > -let message = "original"
  > +let message = "patched"
  > EOF
  $ dune build main.exe
  $ _build/default/main.exe
  patched
