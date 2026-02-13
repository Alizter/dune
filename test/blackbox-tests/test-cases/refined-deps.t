Test refined dependency tracking.

This feature uses ocamlobjinfo to capture the actual .cmi files read by the
compiler and stores them for more precise rebuilds.

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

First, demonstrate the problem WITHOUT refined deps.
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

Now test WITH refined deps enabled:

  $ rm -rf _build

  $ export DUNE_CONFIG__REFINED_DEPS=enabled

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

With refined deps, C's .cmi/.cmx/.cmo should NOT be rebuilt since they only use A:

  $ show_built
  _build/default/lib1/.lib1.objs/lib1__B.impl.d
  _build/default/lib1/.lib1.objs/lib1__B.intf.d
  _build/default/lib1/.lib1.objs/byte/lib1__B.cmi
  _build/default/lib1/.lib1.objs/byte/lib1__B.cmti
  _build/default/lib1/.lib1.objs/native/lib1__B.cmx
  _build/default/lib1/.lib1.objs/native/lib1__B.o
  _build/default/lib1/.lib1.objs/byte/lib1__B.cmo
  _build/default/lib1/.lib1.objs/byte/lib1__B.cmt
  _build/default/lib1/lib1.a
  _build/default/lib1/lib1.cmxa
  _build/default/lib1/lib1.cma
  _build/default/lib1/lib1.cmxs

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

Now test the critical case: changing A (which lib2 DOES use).
C should be rebuilt because it actually reads lib1__A.cmi:

  $ cat > lib1/a.mli << EOF
  > val x : int
  > val x2 : int
  > EOF

  $ cat > lib1/a.ml << EOF
  > let x = 1
  > let x2 = 2
  > EOF

  $ dune build

BUG: C is NOT rebuilt even though A.cmi changed and C uses A.
This is because cross-library .cmi files are not in the refined deps mapping:

  $ show_built | grep lib2__C
  [1]
