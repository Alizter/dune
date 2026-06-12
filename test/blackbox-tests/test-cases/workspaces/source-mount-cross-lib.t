A library in the workspace depends on a public library that lives in
a mounted source tree. The mount context can build its own library;
the workspace cannot resolve the mount's library because the scope DB
does not span the mount yet (task #25 — per-context scope DB).

Mounted source tree: a public library [bar].

  $ mkdir mount-src
  $ cat > mount-src/dune-project << EOF
  > (lang dune 3.25)
  > (package (name bar))
  > EOF
  $ cat > mount-src/dune << EOF
  > (library
  >  (name bar)
  >  (public_name bar))
  > EOF
  $ cat > mount-src/bar.ml << EOF
  > let hello () = print_endline "hello from bar"
  > EOF

Workspace: a public library [foo] that depends on [bar].

  $ mkdir wksp
  $ cd wksp
  $ cat > dune-project << EOF
  > (lang dune 3.25)
  > (package (name foo))
  > EOF
  $ cat > dune << EOF
  > (library
  >  (name foo)
  >  (public_name foo)
  >  (libraries bar))
  > EOF
  $ cat > foo.ml << EOF
  > let go () = Bar.hello ()
  > EOF
  $ cat > dune-workspace << EOF
  > (lang dune 3.25)
  > (context
  >  (default
  >   (mount $PWD/../mount-src)))
  > EOF

The copy rule for [bar.ml] under the mount context's build dir uses
the resolved external path, not a workspace-relative one.

  $ dune rules --format=json _build/default.mount-src/bar.ml | jq '.[0].action'
  [
    "copy",
    "$TESTCASE_ROOT/wksp/../mount-src/bar.ml",
    "_build/default.mount-src/bar.ml"
  ]

Building the mount-context library succeeds.

  $ dune build _build/default.mount-src/bar.cma
  $ test -f _build/default.mount-src/bar.cma && echo built
  built

Workspace context cannot resolve [bar] because the scope DB does not
span the mount.

  $ dune build _build/default/foo.cma 2>&1 | head -5
  File "dune", line 4, characters 12-15:
  4 |  (libraries bar))
                  ^^^
  Error: Library "bar" not found.
  -> required by library "foo" in _build/default
  [1]
