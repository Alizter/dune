Symmetry check: a library in a mount depends on a library in the
workspace (the reverse of cross-lib.t). The sibling fallback should be
bidirectional: both contexts see each other's public libraries.

Workspace declares a public library [base].

  $ cat > dune-project << EOF
  > (lang dune 3.25)
  > (package (name base))
  > EOF
  $ cat > dune << EOF
  > (library
  >  (name base)
  >  (public_name base))
  > EOF
  $ cat > base.ml << EOF
  > let greeting () = "hello"
  > EOF

Mount declares a library [mountlib] depending on [base].

  $ mkdir mount-src
  $ cat > mount-src/dune-project << EOF
  > (lang dune 3.25)
  > (package (name mountlib))
  > EOF
  $ cat > mount-src/dune << EOF
  > (library
  >  (name mountlib)
  >  (public_name mountlib)
  >  (libraries base))
  > EOF
  $ cat > mount-src/mountlib.ml << EOF
  > let go () = print_endline (Base.greeting ())
  > EOF

  $ cat > dune-workspace << EOF
  > (lang dune 3.25)
  > (context
  >  (default
  >   (mount $PWD/mount-src)))
  > EOF

The mount context resolves [base] from the workspace via the sibling
fallback. Mountlib builds.

  $ dune build _build/default.mount-src/mountlib.cma
  $ test -f _build/default.mount-src/mountlib.cma && echo built
  built
