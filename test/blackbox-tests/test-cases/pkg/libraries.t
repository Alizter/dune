The same library can be consumed through native rules or an opaque recipe.
Both cases use the same source and consumer, in independent build roots.

  $ make_external_mypkg_lib_source 'let x = 42'
  $ cat > external_sources/dune <<'EOF'
  > (library
  >  (public_name mypkg.lib)
  >  (name test_lib)
  >  (modules test_lib))
  > (executable (name tool) (modules tool))
  > EOF
  $ echo 'let () = ()' > external_sources/tool.ml
  $ mkdir _consumer native opaque
  $ (cd _consumer && make_dune_project 3.11)
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
  $ make_backend_lockdirs mypkg "$PWD/external_sources"

Describe the cold workspace before compilation. The consumer's executable and
library, and the native dependency's library/modules, are included; the
provider's unrelated executable is not part of the workspace description.

  $ (cd native && dune describe workspace) > native-description
  $ grep -E 'names|\(name ' native-description
    ((names (main))
      (((name Main)
    ((name foo)
      (((name Foo)
    ((name mypkg.lib)
      (((name Test_lib)

The native recipe deliberately fails. Successful compilation and execution
therefore require native loading, without an opaque installation.

  $ (cd native && dune build foo.cma main.exe)
  $ native/_build/default/main.exe
  42
  $ test ! -e native/_build/default/.pkg/mypkg/_install/cookie

The opaque recipe performs a harmless substitution before building the same
Dune project. Its marker and cookie prove this really exercised installation,
not another native build.

  $ (cd opaque && dune describe workspace) > opaque-description
  $ grep -E 'names|\(name ' opaque-description
    ((names (main))
      (((name Main)
    ((name foo)
      (((name Foo)
    ((name mypkg.lib)
  $ (cd opaque && dune build foo.cma main.exe)
  $ opaque/_build/default/main.exe
  42
  $ cat opaque/_build/default/.pkg/mypkg/_install/opaque-recipe
  opaque
  $ test -f opaque/_build/default/.pkg/mypkg/_install/cookie
