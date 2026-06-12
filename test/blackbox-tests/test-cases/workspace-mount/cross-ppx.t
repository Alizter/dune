A workspace library is preprocessed with a PPX defined in a mount
sibling. PPX resolution goes through the host context's Lib.DB, which
has the cross-mount sibling fallback.

Mount defines a no-op PPX rewriter.

  $ mkdir mount-src
  $ cat > mount-src/dune-project << EOF
  > (lang dune 3.25)
  > (package (name mountppx))
  > EOF
  $ cat > mount-src/dune << EOF
  > (library
  >  (name mountppx)
  >  (public_name mountppx)
  >  (kind ppx_rewriter)
  >  (libraries ppxlib))
  > EOF
  $ cat > mount-src/mountppx.ml << EOF
  > let () =
  >   Ppxlib.Driver.register_transformation
  >     "mountppx"
  >     ~impl:(fun s -> s)
  > EOF

Workspace lib uses the PPX.

  $ mkdir wksp
  $ cd wksp
  $ cat > dune-project << EOF
  > (lang dune 3.25)
  > (package (name app))
  > EOF
  $ cat > dune << EOF
  > (library
  >  (name app)
  >  (public_name app)
  >  (preprocess (pps mountppx)))
  > EOF
  $ cat > app.ml << EOF
  > let hello () = "hi"
  > EOF
  $ cat > dune-workspace << EOF
  > (lang dune 3.25)
  > (context
  >  (default
  >   (mount $PWD/../mount-src)))
  > EOF

The PPX resolution in the workspace context's preprocess pipeline
finds [mountppx] in the mount sibling. The library builds.

  $ dune build _build/default/app.cma
  $ test -f _build/default/app.cma && echo built
  built
