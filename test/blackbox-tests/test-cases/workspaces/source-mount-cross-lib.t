A library in the workspace depends on a public library that lives in
a mounted source tree. Today this fails for two reasons.

First, the mount context's rule generation discovers the (library ...)
stanza but cannot read the source file bar.ml through the mount tree
(rules-layer file-resolution still goes through paths that aren't
routed via Source_tree.for_context — task #30).

Second, the workspace context's scope DB does not include the mount's
project, so (libraries bar) in the workspace can't resolve (task #25 —
per-context scope DB).

This test pins both behaviours so the follow-up work has a target to
flip from failure to success.

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

Mount-context library build fails because source files cannot be
resolved through the mount tree.

  $ dune build _build/default.mount-src/bar.cma 2>&1 | head -3
  File "bar.ml", line 1, characters 0-0:
  Error: File unavailable: bar.ml
  [1]

Workspace context cannot resolve [bar] because the scope DB does not
span the mount.

  $ dune build _build/default/foo.cma 2>&1 | head -5
  File "dune", line 4, characters 12-15:
  4 |  (libraries bar))
                  ^^^
  Error: Library "bar" not found.
  -> required by library "foo" in _build/default
  [1]
