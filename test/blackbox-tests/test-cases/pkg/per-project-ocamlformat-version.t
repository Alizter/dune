Test that dune fmt uses the correct ocamlformat version per project.

Each project can specify a different version in its .ocamlformat file,
and dune should use the matching locked tool version.

Helper to create fake ocamlformat source that prints its version:

  $ make_fake_ocamlformat() {
  >   local version=$1
  >   mkdir -p ocamlformat-src
  >   cat > ocamlformat-src/dune-project << EOF
  > (lang dune 3.13)
  > (package (name ocamlformat))
  > EOF
  >   cat > ocamlformat-src/ocamlformat.ml << EOF
  > let () = print_endline "formatted with version $version"
  > EOF
  >   cat > ocamlformat-src/dune << EOF
  > (executable (public_name ocamlformat))
  > EOF
  >   tar cf "ocamlformat-${version}.tar" ocamlformat-src
  >   rm -rf ocamlformat-src
  > }

  $ make_ocamlformat_opam_pkg() {
  >   local version=$1
  >   mkpkg ocamlformat "$version" << EOF
  > build: [["dune" "build" "-p" name "@install"]]
  > url {
  >   src: "file://$PWD/ocamlformat-$version.tar"
  >   checksum: ["md5=$(md5sum "ocamlformat-${version}.tar" | cut -f1 -d' ')"]
  > }
  > EOF
  > }

Set up mock opam repo with two ocamlformat versions:

  $ mkrepo
  $ mkpkg ocaml-system "5.4.0+fake" << EOF
  > flags: compiler
  > EOF
  $ make_fake_ocamlformat 0.26.0
  $ make_ocamlformat_opam_pkg 0.26.0
  $ make_fake_ocamlformat 0.27.0
  $ make_ocamlformat_opam_pkg 0.27.0

Create workspace with two projects requiring different versions:

  $ cat > dune-project << EOF
  > (lang dune 3.16)
  > EOF

  $ cat > dune-workspace << EOF
  > (lang dune 3.20)
  > (repository
  >  (name mock)
  >  (url "file://$PWD/mock-opam-repository"))
  > (lock_dir
  >  (repositories mock))
  > (tool
  >  (package ocamlformat)
  >  (repositories mock))
  > EOF

  $ mkdir -p project-a project-b

Project A wants ocamlformat 0.26.0:

  $ cat > project-a/dune-project << EOF
  > (lang dune 3.16)
  > EOF
  $ cat > project-a/.ocamlformat << EOF
  > version = 0.26.0
  > EOF
  $ cat > project-a/dune << EOF
  > (library (name a))
  > EOF
  $ cat > project-a/a.ml << EOF
  > let x=1
  > EOF

Project B wants ocamlformat 0.27.0:

  $ cat > project-b/dune-project << EOF
  > (lang dune 3.16)
  > EOF
  $ cat > project-b/.ocamlformat << EOF
  > version = 0.27.0
  > EOF
  $ cat > project-b/dune << EOF
  > (library (name b))
  > EOF
  $ cat > project-b/b.ml << EOF
  > let y=2
  > EOF

Without any tool locked, dune fmt should tell us to add the tools:

  $ dune build @fmt 2>&1
  Error:
  ocamlformat version 0.26.0 is required by project-a/.ocamlformat
  but is not available. Run:
    dune tools add ocamlformat.0.26.0

  -> required by alias project-a/fmt
  Error:
  ocamlformat version 0.27.0 is required by project-b/.ocamlformat
  but is not available. Run:
    dune tools add ocamlformat.0.27.0

  -> required by alias project-b/fmt
  [1]

Now add both versions:

  $ dune tools add ocamlformat.0.26.0 ocamlformat.0.27.0
  Locked ocamlformat@0.26.0
  Locked ocamlformat@0.27.0

Running dune fmt should now use the correct version for each project:

  $ dune build @fmt 2>&1
  File "project-a/a.ml", line 1, characters 0-0:
  Error: Files _build/default/project-a/a.ml and
  _build/default/project-a/.formatted/a.ml differ.
  File "project-b/b.ml", line 1, characters 0-0:
  Error: Files _build/default/project-b/b.ml and
  _build/default/project-b/.formatted/b.ml differ.
  [1]

Verify each project used the correct version:

  $ cat _build/default/project-a/.formatted/a.ml
  formatted with version 0.26.0

  $ cat _build/default/project-b/.formatted/b.ml
  formatted with version 0.27.0
