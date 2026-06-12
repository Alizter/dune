A package defined in a mount has its install rules emitted under the
mount context's install dir. This works without any cross-context
install-rule plumbing — install rules are already per-context, and
each mount internal context emits its own.

  $ mkdir mount-src
  $ cat > mount-src/dune-project << EOF
  > (lang dune 3.25)
  > (package (name mountpkg))
  > EOF
  $ cat > mount-src/dune << EOF
  > (library
  >  (name mountpkg)
  >  (public_name mountpkg))
  > EOF
  $ cat > mount-src/mountpkg.ml << EOF
  > let hello () = print_endline "hello from mountpkg"
  > EOF

  $ mkdir wksp
  $ cd wksp
  $ cat > dune-project << EOF
  > (lang dune 3.25)
  > EOF
  $ cat > dune-workspace << EOF
  > (lang dune 3.25)
  > (context
  >  (default
  >   (mount $PWD/../mount-src)))
  > EOF

The mount context's install rules produce install artefacts at
[_build/install/default.mount-src/lib/mountpkg/].

  $ dune build @install
  $ ls _build/install/default.mount-src/lib/mountpkg | sort
  META
  dune-package
  mountpkg.a
  mountpkg.cma
  mountpkg.cmi
  mountpkg.cmt
  mountpkg.cmx
  mountpkg.cmxa
  mountpkg.cmxs
  mountpkg.ml
