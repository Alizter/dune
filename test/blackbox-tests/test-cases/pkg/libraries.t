The same library can be consumed through native rules or an opaque recipe.
Both cases use the same source and consumer, in independent build roots.

  $ make_external_mypkg_lib_source 'let x = 42'
  $ mkdir _consumer native opaque
  $ cat > _consumer/dune-project <<'EOF'
  > (lang dune 3.11)
  > EOF
  $ cat > _consumer/dune <<'EOF'
  > (library
  >  (name foo)
  >  (modules foo)
  >  (libraries mypkg.lib))
  > (executable
  >  (name main)
  >  (modules main)
  >  (libraries foo))
  > EOF
  $ echo 'let x = Test_lib.x' > _consumer/foo.ml
  $ echo 'let () = Printf.printf "%d\n" Foo.x' > _consumer/main.ml
  $ cp _consumer/* native/
  $ cp _consumer/* opaque/
  $ (cd native && make_lockdir &&
  >  make_dune_source_lockpkg native mypkg "$PWD/../external_sources")
  $ (cd opaque && make_lockdir &&
  >  make_dune_source_lockpkg opaque mypkg "$PWD/../external_sources")

The native recipe deliberately fails. Successful compilation and execution
therefore require native loading, without an opaque installation.

  $ (cd native && dune build foo.cma main.exe)
  $ native/_build/default/main.exe
  42
  $ test ! -e native/_build/default/.pkg/mypkg/_install/cookie
  $ test ! -e native/_build/default/.pkg/mypkg/_install/opaque-recipe

The opaque recipe performs a harmless substitution before building the same
Dune project. Its marker and cookie prove this really exercised installation,
not another native build.

  $ (cd opaque && dune build foo.cma main.exe)
  $ opaque/_build/default/main.exe
  42
  $ cat opaque/_build/default/.pkg/mypkg/_install/opaque-recipe
  opaque
  $ test -f opaque/_build/default/.pkg/mypkg/_install/cookie
  $ test ! -e external_sources/opaque-recipe
