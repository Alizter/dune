A workspace rule references a mount-defined library via [%{cma:bar}].
The Artifact pform [Lib] falls back to the scope's public_libs Lib.DB
(which carries the cross-mount sibling fallback) when the per-dir
[Artifacts_obj.t] doesn't have the library locally.

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

  $ mkdir wksp
  $ cd wksp
  $ cat > dune-project << EOF
  > (lang dune 3.25)
  > EOF
  $ cat > dune << EOF
  > (rule
  >  (target out)
  >  (action (with-stdout-to %{target} (echo "%{cma:bar}"))))
  > EOF
  $ cat > dune-workspace << EOF
  > (lang dune 3.25)
  > (context
  >  (default
  >   (mount $PWD/../mount-src)))
  > EOF

  $ dune build out
  $ cat _build/default/out
  ../default.mount-src/bar.cma
