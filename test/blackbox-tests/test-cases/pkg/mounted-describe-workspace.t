`dune describe workspace` describes the workspace, not the locked packages
mounted in the build context.

  $ make_lockdir
  $ cat > dune-project <<'EOF2'
  > (lang dune 3.25)
  > (package (name main) (allow_empty) (depends foo))
  > EOF2
  $ echo '(executable (name main) (libraries foo))' > dune
  $ echo 'let () = print_endline Foo.message' > main.ml
  $ mkdir _source
  $ cat > _source/dune-project <<'EOF2'
  > (lang dune 3.25)
  > (package (name foo))
  > EOF2
  $ cat > _source/dune <<'EOF2'
  > (library (public_name foo) (modules foo))
  > (executable (name tool) (modules tool))
  > EOF2
  $ echo 'let message = "mounted"' > _source/foo.ml
  $ echo 'let () = ()' > _source/tool.ml
  $ make_lockpkg foo <<EOF2
  > (version 1.0)
  > (source (copy $PWD/_source))
  > (build (run false))
  > EOF2
  $ echo '(dirs :standard \ _source)' >> dune

  $ dune describe workspace 2>&1 | grep -E 'names|\(name '
    ((names (main))
      (((name Main)
    ((name foo)
      (((name Foo)
