A dune file in OCaml syntax is a program. For a mounted package it does not
run in the fetched source, which is shared by every package built from it.

  $ make_lockdir
  $ make_named_package_project main 3.25 foo
  $ mkdir _source
  $ (cd _source && make_dune_project_with_package 3.25 foo)
  $ cat > _source/dune <<'EOF2'
  > (* -*- tuareg -*- *)
  > let () =
  >   close_out (open_out "written-by-script");
  >   Jbuild_plugin.V1.send {|(rule (with-stdout-to out (echo generated)))|}
  > EOF2
  $ make_dune_source_lockpkg native foo "$PWD/_source"
  $ dune build _build/default/.pkg/foo/out
  $ cat _build/default/.pkg/foo/out
  generated

The file the script wrote:

  $ find _build -name written-by-script | sed -E 's#_fetch/[a-z]+/[^/]+#_fetch/$HASH#'
  _build/_private/default/.dune-source/foo/source/written-by-script
  $ test ! -e _source/written-by-script

Because the script wrote into the private copy, the next build makes the copy
again. A script that writes nothing leaves it alone.

  $ copy=_build/_private/default/.dune-source/foo/source/dune-project
  $ ln $copy before
  $ dune build _build/default/.pkg/foo/out
  $ test ! $copy -ef before
  $ cat > _source/dune <<'EOF2'
  > (* -*- tuareg -*- *)
  > let () = Jbuild_plugin.V1.send {|(rule (with-stdout-to out (echo generated)))|}
  > EOF2
  $ dune build _build/default/.pkg/foo/out
  $ ln -f $copy before
  $ dune build _build/default/.pkg/foo/out
  $ test $copy -ef before
