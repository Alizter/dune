A rocq theory with (generate_project_file) writes a _RocqProject whose -R and
-Q entries are given twice when the build and source directories differ, so
that the file works from either (rocq/coqproject.t). A mounted theory's source
directory is its build directory, and a mount is never promoted into.

  $ make_lockdir
  $ cat > dune-project <<'EOF'
  > (lang dune 3.25)
  > (package (name main) (depends foo))
  > EOF
  $ mkdir -p _source/thy
  $ cat > _source/dune-project <<'EOF'
  > (lang dune 3.25)
  > (using rocq 0.11)
  > (package (name foo) (dir .))
  > EOF
  $ cat > _source/thy/dune <<'EOF'
  > (rocq.theory
  >  (name a)
  >  (generate_project_file))
  > EOF
  $ touch _source/thy/foo.v
  $ make_dune_source_lockpkg native foo "$PWD/_source"
  $ mount=_build/default/.pkg/foo

The mounted file is written in the build directory only, which is also the
theory's source directory, so one entry suffices.

  $ dune build $mount/thy/_RocqProject 2>&1 && grep -E '^-[RQ] .* a$' $mount/thy/_RocqProject
  -R . a
  $ test ! -e _source/thy/_RocqProject

The workspace file is promoted next to the sources and names the build
directory from there.

  $ (cd _source && dune build --root . thy/_RocqProject 2>&1 && grep -E '^-[RQ] .* a$' thy/_RocqProject)
  -R . a
  -R ../_build/default/thy a
