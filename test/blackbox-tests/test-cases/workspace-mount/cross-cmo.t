A workspace rule references a module artifact ([%{cmo:Foo}]) defined
in a mount sibling. Module artifact lookup is keyed by build path,
which differs across contexts; the cross-mount fallback translates the
path to each sibling's context-build-dir.

  $ mkdir mount-src
  $ cat > mount-src/dune-project << EOF
  > (lang dune 3.25)
  > EOF
  $ cat > mount-src/dune << EOF
  > (executable
  >  (name mountmod))
  > EOF
  $ cat > mount-src/mountmod.ml << EOF
  > let () = ()
  > EOF

  $ mkdir wksp
  $ cd wksp
  $ cat > dune-project << EOF
  > (lang dune 3.25)
  > EOF
  $ cat > dune << EOF
  > (rule
  >  (target out)
  >  (action (with-stdout-to %{target} (echo "%{cmo:mountmod}"))))
  > EOF
  $ cat > dune-workspace << EOF
  > (lang dune 3.25)
  > (context
  >  (default
  >   (mount $PWD/../mount-src)))
  > EOF

  $ dune build out
  $ cat _build/default/out
  ../default.mount-src/.mountmod.eobjs/byte/dune__exe__Mountmod.cmo
