We try to load a module defined in a library with a dependnecy

  $ cat >dune-project <<EOF
  > (lang dune 3.3)
  > EOF

  $ mkdir foo
  $ cd foo

  $ cat >bar.ml <<EOF
  > let v = 42
  > EOF

  $ cat >foo.ml <<EOF
  > let foo = Bar.v + 42
  > EOF

  $ cat >dune <<EOF
  > (library
  >  (libraries mydummylib)
  >  (name foo))
  > EOF

  $ cd ..

  $ mkdir mydummylib
  $ cd mydummylib
  $ cat >dune <<EOF
  > (library (name mydummylib))
  > EOF
  $ touch mydummylib.ml
  $ touch blabla.ml

  $ cd ..

  $ dune ocaml top-module foo/foo.ml
  #directory "$TESTCASE_ROOT/_build/default/.topmod/foo/foo.ml";;
  #directory "$TESTCASE_ROOT/_build/default/mydummylib/.mydummylib.objs/byte";;
  #load "$TESTCASE_ROOT/_build/default/mydummylib/mydummylib.cma";;
  #load "$TESTCASE_ROOT/_build/default/foo/.foo.objs/byte/foo__.cmo";;
  #load "$TESTCASE_ROOT/_build/default/foo/.foo.objs/byte/foo__Bar.cmo";;
  #load "$TESTCASE_ROOT/_build/default/.topmod/foo/foo.ml/foo.cmo";;
  open Foo__
  ;;

  $ ls _build/default/.topmod/foo/foo.ml
  foo.cmi
  foo.cmo
  foo__.cmi
  foo__Bar.cmi

  $ ls _build/default/mydummylib/.mydummylib.objs/byte/*.cmi
  _build/default/mydummylib/.mydummylib.objs/byte/mydummylib.cmi
  _build/default/mydummylib/.mydummylib.objs/byte/mydummylib__.cmi
  _build/default/mydummylib/.mydummylib.objs/byte/mydummylib__Blabla.cmi

  $ ls _build/default/mydummylib/*.cma
  _build/default/mydummylib/mydummylib.cma

  $ dune ocaml top-module $PWD/foo/foo.ml
  Internal error, please report upstream including the contents of _build/log.
  Description:
    ("Local.relative: received absolute path",
    { t = "."
    ; path =
        "$TESTCASE_ROOT/foo/foo.ml"
    })
  Raised at Stdune__Code_error.raise in file
    "otherlibs/stdune/src/code_error.ml", line 11, characters 30-62
  Called from Stdune__Path.Local_gen.relative in file
    "otherlibs/stdune/src/path.ml", line 251, characters 6-114
  Called from Dune__exe__Top.Module.term.(fun) in file "bin/ocaml/top.ml", line
    226, characters 16-115
  Called from Fiber__Scheduler.exec in file "otherlibs/fiber/src/scheduler.ml",
    line 73, characters 8-11
  Re-raised at Stdune__Exn.raise_with_backtrace in file
    "otherlibs/stdune/src/exn.ml", line 36, characters 27-56
  Called from Fiber__Scheduler.exec in file "otherlibs/fiber/src/scheduler.ml",
    line 73, characters 8-11
  
  I must not crash.  Uncertainty is the mind-killer. Exceptions are the
  little-death that brings total obliteration.  I will fully express my cases. 
  Execution will pass over me and through me.  And when it has gone past, I
  will unwind the stack along its path.  Where the cases are handled there will
  be nothing.  Only I will remain.
  [1]
