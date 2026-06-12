A workspace rule has a [(deps (package mountpkg))] dependency on a
package declared in a mount sibling. [Package_db.find_package] falls
back to siblings when the local context doesn't declare the package.

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
  > let hello () = ()
  > EOF

  $ mkdir wksp
  $ cd wksp
  $ cat > dune-project << EOF
  > (lang dune 3.25)
  > EOF
  $ cat > dune << EOF
  > (rule
  >  (target out)
  >  (deps (package mountpkg))
  >  (action (with-stdout-to %{target} (echo "ok"))))
  > EOF
  $ cat > dune-workspace << EOF
  > (lang dune 3.25)
  > (context
  >  (default
  >   (mount $PWD/../mount-src)))
  > EOF

The package is resolved from the mount sibling. The dep machinery may
still warn about missing install rules (Phase 6), but the package
lookup itself succeeds.

  $ dune build out
  $ cat _build/default/out
  ok
