A workspace rule references a mount-defined library via the
[%{lib:bar:archives}] macro. The lib lookup now correctly derives the
install context from the lib's own build dir (rather than the
expander's context), so the lookup path points at the mount context's
install dir. The install rules themselves are still emitted only
per-internal-context, so cross-mount install path resolution awaits
Phase 6 (install rules cross-context).

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

Workspace consults [bar] via the macro from a rule.

  $ mkdir wksp
  $ cd wksp
  $ cat > dune-project << EOF
  > (lang dune 3.25)
  > EOF
  $ cat > dune << EOF
  > (rule
  >  (target archives.txt)
  >  (action (with-stdout-to %{target} (echo "%{lib:bar:archives}"))))
  > EOF
  $ cat > dune-workspace << EOF
  > (lang dune 3.25)
  > (context
  >  (default
  >   (mount $PWD/../mount-src)))
  > EOF

The lookup resolves to the mount's install context. The rule for the
archives file is missing until Phase 6.

  $ dune build archives.txt 2>&1 | head -5
  File "dune", lines 1-3, characters 0-95:
  1 | (rule
  2 |  (target archives.txt)
  3 |  (action (with-stdout-to %{target} (echo "%{lib:bar:archives}"))))
  Error: No rule found for default.mount-src/lib/bar/archives (context install)
  [1]
