A mounted package may copy source files from a child directory. Enumerating the
logical source directory must not recurse through rule generation for its parent.

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

  $ mkdir -p foo/files
  $ cat > foo/dune-project <<'EOF'
  > (lang dune 3.20)
  > (package (name foo))
  > EOF
  $ cat > foo/dune <<'EOF'
  > (copy_files files/*.ml)
  > (library
  >  (name foo)
  >  (public_name foo))
  > EOF
  $ cat > foo/foo.ml <<'EOF'
  > let message = Payload.message
  > EOF
  $ cat > foo/files/payload.ml <<'EOF'
  > let message = "copied"
  > EOF
  $ tar cf foo.tar foo
  $ rm -rf foo

  $ make_lockdir
  $ make_lockpkg foo <<EOF
  > (version 1.0)
  > (source (copy $PWD/foo.tar))
  > (build (run dune build @install))
  > EOF

  $ dune build ./main.exe --display quiet
  $ ./_build/default/main.exe
  copied

A sibling source glob must not reload the mounted package root while compile
command collection is inspecting the destination library.

  $ mkdir sibling
  $ cd sibling
  $ cat > dune-workspace <<'EOF'
  > (lang dune 3.23)
  > (pkg enabled)
  > EOF
  $ cat > dune-project <<'EOF'
  > (lang dune 3.23)
  > (package
  >  (name main)
  >  (depends bar))
  > EOF
  $ cat > dune <<'EOF'
  > (executable
  >  (name main)
  >  (libraries bar))
  > EOF
  $ cat > main.ml <<'EOF'
  > let () = print_endline Bar.message
  > EOF

  $ mkdir -p bar/lib bar/lib_test/expect
  $ cat > bar/dune-project <<'EOF'
  > (lang dune 3.20)
  > (package (name bar))
  > EOF
  $ cat > bar/lib/dune <<'EOF'
  > (library
  >  (name bar)
  >  (public_name bar))
  > EOF
  $ cat > bar/lib/bar.ml <<'EOF'
  > let message = "copied from sibling"
  > EOF
  $ cat > bar/lib_test/expect/dune <<'EOF'
  > (subdir
  >  private_bar
  >  (library
  >   (name bar_private))
  >  (copy_files %{project_root}/lib/*.ml))
  > EOF
  $ tar cf bar.tar bar
  $ rm -rf bar

  $ make_lockdir
  $ make_lockpkg bar <<EOF
  > (version 1.0)
  > (source (copy $PWD/bar.tar))
  > (build (run dune build @install))
  > EOF

  $ dune build ./main.exe --display quiet
  $ ./_build/default/main.exe
  copied from sibling
