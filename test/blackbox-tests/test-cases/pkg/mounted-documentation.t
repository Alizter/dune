Automatic documentation installation and generated documentation consume the
same source/package inventories in the workspace and in a mount, including a
selected nested project.

  $ make_dune_project 3.25
  $ make_lockdir
  $ mkdir -p _source/project
  $ echo '(lang dune 3.25)' > _source/dune-project
  $ cat > _source/project/dune-project <<'EOF'
  > (lang dune 3.25)
  > (package (name foo))
  > (package (name omitted))
  > EOF
  $ echo '(library (public_name foo))' > _source/project/dune
  $ echo 'let value = 42' > _source/project/foo.ml
  $ make_dune_source_lockpkg native foo "$PWD/_source"
  $ (cd _source && dune build --root . --only-packages foo project/foo.install)
  $ dune build _build/default/.pkg/foo/project/foo.install

Adding documentation invalidates the existing installation inventories.

  $ echo 'package readme' > _source/project/README.md
  $ echo 'package license' > _source/project/LICENSE
  $ echo '{0 Guide}' > _source/project/guide.mld
  $ cat >> _source/project/dune <<'EOF'
  > (documentation (package foo) (mld_files guide))
  > EOF
  $ (cd _source && dune build --root . --only-packages foo \
  >   project/foo.install @project/doc)
  $ grep -q 'README.md' _source/_build/default/project/foo.install
  $ grep -q 'LICENSE' _source/_build/default/project/foo.install
  $ test -f _source/_build/default/_doc/_html/foo/guide.html
  $ cat > dune <<'EOF'
  > (rule
  >  (target readme)
  >  (action (copy %{pkg:foo:doc:README.md} %{target})))
  > EOF
  $ dune build readme @_build/default/.pkg/foo/project/doc
  $ cat _build/default/readme
  package readme
  $ test -f _build/default/_doc/_html/foo/guide.html
  $ dune build _build/default/.pkg/foo/project/foo.install
  $ grep -q 'README.md' _build/default/.pkg/foo/project/foo.install
  $ grep -q 'LICENSE' _build/default/.pkg/foo/project/foo.install
  $ echo 'updated readme' > _source/project/README.md
  $ dune build readme
  $ cat _build/default/readme
  updated readme
