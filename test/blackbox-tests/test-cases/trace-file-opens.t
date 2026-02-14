Test refined dependency tracking via syscall tracing.

This feature uses seccomp-bpf + ptrace to trace file opens during action
execution and captures actual files read by the compiler for more precise rebuilds.

Helper to show targets built in the last run:

  $ show_built() {
  >   dune trace cat | jq -r '
  >     include "dune";
  >     [ processes | .args.target_files[]? | select(test("lib[12]")) ]
  >     | sort | .[]'
  > }

Setup: Create two libraries where lib2 depends on lib1.

  $ cat > dune-project << EOF
  > (lang dune 3.0)
  > EOF

  $ mkdir lib1 lib2

Library 1 has two modules: A (used by lib2) and B (not used by lib2):

  $ cat > lib1/dune << EOF
  > (library
  >  (name lib1))
  > EOF

  $ cat > lib1/a.ml << EOF
  > let x = 1
  > EOF

  $ cat > lib1/a.mli << EOF
  > val x : int
  > EOF

  $ cat > lib1/b.ml << EOF
  > let y = 2
  > EOF

  $ cat > lib1/b.mli << EOF
  > val y : int
  > EOF

Library 2 only uses A from lib1:

  $ cat > lib2/dune << EOF
  > (library
  >  (name lib2)
  >  (libraries lib1))
  > EOF

  $ cat > lib2/c.ml << EOF
  > let z = Lib1.A.x + 1
  > EOF

  $ cat > lib2/c.mli << EOF
  > val z : int
  > EOF

First, demonstrate the problem WITHOUT traced file opens.
Build initially:

  $ dune build

Now change B (which lib2 doesn't use) and rebuild:

  $ cat > lib1/b.mli << EOF
  > val y : int
  > val y2 : int
  > EOF

  $ cat > lib1/b.ml << EOF
  > let y = 2
  > let y2 = 3
  > EOF

  $ dune build

Check what was rebuilt - show all targets from lib1 and lib2:

  $ show_built
  _build/default/lib1/.lib1.objs/lib1__B.impl.d
  _build/default/lib1/.lib1.objs/lib1__B.intf.d
  _build/default/lib1/.lib1.objs/byte/lib1__B.cmi
  _build/default/lib1/.lib1.objs/byte/lib1__B.cmti
  _build/default/lib1/.lib1.objs/native/lib1__B.cmx
  _build/default/lib1/.lib1.objs/native/lib1__B.o
  _build/default/lib1/.lib1.objs/byte/lib1__B.cmo
  _build/default/lib1/.lib1.objs/byte/lib1__B.cmt
  _build/default/lib2/.lib2.objs/byte/lib2__C.cmi
  _build/default/lib2/.lib2.objs/byte/lib2__C.cmti
  _build/default/lib1/lib1.a
  _build/default/lib1/lib1.cmxa
  _build/default/lib1/lib1.cma
  _build/default/lib2/.lib2.objs/native/lib2__C.cmx
  _build/default/lib2/.lib2.objs/native/lib2__C.o
  _build/default/lib2/.lib2.objs/byte/lib2__C.cmo
  _build/default/lib2/.lib2.objs/byte/lib2__C.cmt
  _build/default/lib1/lib1.cmxs

Now test WITH traced file opens enabled:

  $ rm -rf _build

  $ export DUNE_CONFIG__TRACE_FILE_OPENS=enabled

Build initially:

  $ dune build

Change B again:

  $ cat > lib1/b.mli << EOF
  > val y : int
  > val y2 : int
  > val y3 : int
  > EOF

  $ cat > lib1/b.ml << EOF
  > let y = 2
  > let y2 = 3
  > let y3 = 4
  > EOF

  $ dune build

With traced file opens, C's .cmi/.cmx/.cmo should NOT be rebuilt since they only use A:

  $ show_built
  _build/default/lib1/.lib1.objs/lib1__B.impl.d
  _build/default/lib1/.lib1.objs/lib1__B.intf.d
  _build/default/lib1/.lib1.objs/byte/lib1__B.cmi
  _build/default/lib1/.lib1.objs/byte/lib1__B.cmti
  _build/default/lib1/.lib1.objs/native/lib1__B.cmx
  _build/default/lib1/.lib1.objs/native/lib1__B.o
  _build/default/lib1/lib1.a
  _build/default/lib1/lib1.cmxa
  _build/default/lib1/.lib1.objs/byte/lib1__B.cmo
  _build/default/lib1/.lib1.objs/byte/lib1__B.cmt
  _build/default/lib1/lib1.cma
  _build/default/lib1/lib1.cmxs
  _build/default/lib2/.lib2.objs/native/lib2__C.cmx
  _build/default/lib2/.lib2.objs/native/lib2__C.o
  _build/default/lib2/.lib2.objs/byte/lib2__C.cmo
  _build/default/lib2/.lib2.objs/byte/lib2__C.cmt

Now verify that changing the SOURCE file (c.ml) DOES trigger a rebuild:

  $ cat > lib2/c.ml << EOF
  > let z = Lib1.A.x + 999
  > EOF

  $ dune build

C's .cmx and .cmo SHOULD be rebuilt since the source changed:

  $ show_built | grep lib2__C
  _build/default/lib2/.lib2.objs/lib2__C.impl.d
  _build/default/lib2/.lib2.objs/native/lib2__C.cmx
  _build/default/lib2/.lib2.objs/native/lib2__C.o
  _build/default/lib2/.lib2.objs/byte/lib2__C.cmo
  _build/default/lib2/.lib2.objs/byte/lib2__C.cmt

Show refinement for lib2__C to understand what deps are tracked:

  $ dune trace cat 2>/dev/null | jq 'select(.name == "refined") | select(.args.head | test("lib2__C.cmx")) | {head: .args.head, actual: .args.actual_deps, traced: .args.traced_build, refined: .args.refined_deps}'
  {
    "head": "_build/default/lib2/.lib2.objs/native/lib2__C.cmx",
    "actual": [
      "/nix/store/0gxysxzzvzqm2m2aznix02pm05bmqm1q-ocaml+fp-5.4.0/bin/ocamlopt.opt",
      "_build/default/lib1/.lib1.objs/byte/lib1.cmi",
      "_build/default/lib1/.lib1.objs/byte/lib1__A.cmi",
      "_build/default/lib1/.lib1.objs/byte/lib1__B.cmi",
      "_build/default/lib2/.lib2.objs/byte/lib2.cmi",
      "_build/default/lib2/.lib2.objs/byte/lib2__C.cmi",
      "_build/default/lib2/c.ml"
    ],
    "traced": [
      "_build/default",
      "_build/default/lib1/.lib1.objs/byte",
      "_build/default/lib1/.lib1.objs/byte/lib1.cmi",
      "_build/default/lib1/.lib1.objs/byte/lib1__A.cmi",
      "_build/default/lib1/.lib1.objs/native",
      "_build/default/lib2/.lib2.objs/byte",
      "_build/default/lib2/.lib2.objs/byte/lib2.cmi",
      "_build/default/lib2/.lib2.objs/byte/lib2__C.cmi",
      "_build/default/lib2/.lib2.objs/native",
      "_build/default/lib2/.lib2.objs/native/lib2__C.cmx",
      "_build/default/lib2/.lib2.objs/native/lib2__C.o",
      "_build/default/lib2/c.ml"
    ],
    "refined": [
      "/nix/store/0gxysxzzvzqm2m2aznix02pm05bmqm1q-ocaml+fp-5.4.0/bin/ocamlopt.opt",
      "_build/default/lib1/.lib1.objs/byte/lib1.cmi",
      "_build/default/lib1/.lib1.objs/byte/lib1__A.cmi",
      "_build/default/lib1/.lib1.objs/byte/lib1__B.cmi",
      "_build/default/lib2/.lib2.objs/byte/lib2.cmi",
      "_build/default/lib2/.lib2.objs/byte/lib2__C.cmi",
      "_build/default/lib2/c.ml"
    ]
  }

Now test the critical case: changing A (which lib2 DOES use).
C should be rebuilt because we traced that it actually reads lib1__A.cmi:

  $ cat > lib1/a.mli << EOF
  > val x : int
  > val x2 : int
  > EOF

  $ cat > lib1/a.ml << EOF
  > let x = 1
  > let x2 = 2
  > EOF

  $ dune build

C SHOULD be rebuilt because A.cmi changed and C uses A:

  $ show_built | grep lib2__C
  _build/default/lib2/.lib2.objs/native/lib2__C.cmx
  _build/default/lib2/.lib2.objs/native/lib2__C.o
  _build/default/lib2/.lib2.objs/byte/lib2__C.cmo
  _build/default/lib2/.lib2.objs/byte/lib2__C.cmt
