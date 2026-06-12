A library in the workspace depends on a public library that lives in
a mounted source tree. The Lib.DB sibling fallback in the rules layer
makes [(libraries bar)] resolve [bar] from the mount.

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
the resolved external path.

  $ dune rules --format=json _build/default.mount-src/bar.ml | jq '.[0].action'
  [
    "copy",
    "$TESTCASE_ROOT/wksp/../mount-src/bar.ml",
    "_build/default.mount-src/bar.ml"
  ]

The mount context builds its own library.

  $ dune build _build/default.mount-src/bar.cma
  $ test -f _build/default.mount-src/bar.cma && echo built
  built

The workspace context resolves [bar] via the sibling fallback and
builds [foo.cma]. [bar]'s artifacts live in the mount context's build
dir; [foo.cma] links against them across contexts.

  $ dune build _build/default/foo.cma
  $ test -f _build/default/foo.cma && echo foo-built
  foo-built
