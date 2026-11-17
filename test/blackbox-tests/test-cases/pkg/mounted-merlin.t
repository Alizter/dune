Merlin configuration for a library mounted from a lock directory. Its source
directories are in the mount (workspace libraries: merlin/src-dirs-of-deps.t).

  $ make_lockdir
  $ make_named_package_project main 3.25 foo
  $ mkdir -p _source/lib bin
  $ (cd _source && make_dune_project_with_package 3.25 foo)
  $ cat > _source/lib/dune <<'EOF2'
  > (library (public_name foo))
  > EOF2
  $ echo 'let x = 1' > _source/lib/a.ml
  $ echo 'val x : int' > _source/lib/a.mli
  $ echo 'let y = A.x' > _source/lib/b.ml
  $ make_dune_source_lockpkg native foo "$PWD/_source"
  $ cat > bin/dune <<'EOF2'
  > (executable (name main) (libraries foo))
  > EOF2
  $ echo 'let () = print_int Foo.B.y' > bin/main.ml
  $ opam_prefix="$(ocamlc -where)"
  $ export BUILD_PATH_PREFIX_MAP="/OPAM_PREFIX=$opam_prefix:$BUILD_PATH_PREFIX_MAP"

The library through the mount:

  $ mount=$pkg_root/foo
  $ dune build $mount/lib/.merlin-conf/lib-foo 2>&1
  $ dune ocaml merlin dump-config --format=json $PWD/$mount/lib 2>&1 | jq_dune -r 'merlinEntry("A") | merlinJsonEntryWithConfigNames(["S", "UNIT_NAME"])'
  A: _build/default/.pkg/foo/lib/a
  ["S","$TESTCASE_ROOT/_build/default/.pkg/foo/lib"]
  ["UNIT_NAME","foo__A"]
  A: _build/default/.pkg/foo/lib/a.ml
  ["S","$TESTCASE_ROOT/_build/default/.pkg/foo/lib"]
  ["UNIT_NAME","foo__A"]
  A: _build/default/.pkg/foo/lib/a.mli
  ["S","$TESTCASE_ROOT/_build/default/.pkg/foo/lib"]
  ["UNIT_NAME","foo__A"]

A workspace executable using the mounted library: the library's sources
must be listed so that definitions can be found.

  $ dune build bin/.merlin-conf/exe-main 2>&1
  $ dune ocaml merlin dump-config --format=json $PWD/bin 2>&1 | jq_dune -r 'merlinEntry("Main") | merlinJsonEntryWithConfigNames(["S", "UNIT_NAME"])'
  Main: _build/default/bin/main
  ["S","$TESTCASE_ROOT/bin"]
  ["S","$TESTCASE_ROOT/_build/default/.pkg/foo/lib"]
  ["UNIT_NAME","dune__exe__Main"]
  Main: _build/default/bin/main.ml
  ["S","$TESTCASE_ROOT/bin"]
  ["S","$TESTCASE_ROOT/_build/default/.pkg/foo/lib"]
  ["UNIT_NAME","dune__exe__Main"]
  Main: _build/default/bin/main.mli
  ["S","$TESTCASE_ROOT/bin"]
  ["S","$TESTCASE_ROOT/_build/default/.pkg/foo/lib"]
  ["UNIT_NAME","dune__exe__Main"]
