When a lock dir contains a [(build (dune))] package whose source is a
git fetch (Fetch source kind, so [source_dir] is a directory target),
the pkg-mount synthesiser materialises an internal context whose
source tree is rooted at the pkg's [source_dir]. This test surfaces
how that interaction behaves end-to-end.

  $ mkrepo
  $ add_mock_repo_if_needed

Set up a git-backed dependency that builds with dune.

  $ mkdir _dep
  $ cd _dep
  $ git init -q --initial-branch=main
  $ cat > dune-project << EOF
  > (lang dune 3.25)
  > (package (name dep))
  > EOF
  $ cat > dep.ml << EOF
  > let value = "from dep"
  > EOF
  $ cat > dune << EOF
  > (library (public_name dep))
  > EOF
  $ git add -A
  $ git commit -qm "initial"
  $ cd ..

Pin the dependency via [git+file://] so the lockfile records a Fetch
source. With [(build (dune))] implied by the dune-project, this is
exactly the case the pkg-mount synthesiser targets.

  $ cat > main.ml << EOF
  > print_endline Dep.value
  > EOF
  $ cat > dune << EOF
  > (executable (name main) (libraries dep))
  > EOF
  $ cat > dune-project << EOF
  > (lang dune 3.25)
  > (pin (url "git+file://$PWD/_dep") (package (name dep)))
  > (package (name main) (depends dep))
  > EOF

Lock then build. With the pkg-mount synthesiser active, this should
produce the dep source mount and build through it.

  $ dune pkg lock 2> /dev/null
  $ dune exec ./main.exe 2>&1 | head -30
  from dep

The pkg-mount synthesiser should have materialised a sibling context
for [dep]. The internal context name is [default.dep], with its build
dir under [_build/default.dep/].

  $ ls _build | grep -E '^default' | sort
  default
  default.dep
