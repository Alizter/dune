When a lock dir contains a [(build (dune))] package whose source is a
fetched tarball (Fetch source kind, so [source_dir] is a directory
target), the pkg-mount synthesiser materialises an internal context
whose source tree is rooted at the unpacked tarball under
[source_dir]. This is the canonical "published opam package" shape:
an HTTP tarball URL with a checksum.

  $ make_lockdir

Build a tarball that ships a dune-project + dune file + library
source for a dep package.

  $ mkdir _sources
  $ cat > _sources/dune-project << EOF
  > (lang dune 3.25)
  > (package (name dep))
  > EOF
  $ cat > _sources/dep.ml << EOF
  > let value = "from tarball"
  > EOF
  $ cat > _sources/dune << EOF
  > (library (public_name dep))
  > EOF
  $ tar cf dep.tar _sources
  $ checksum=$(md5sum dep.tar | awk '{ print $1 }')
  $ echo dep.tar > fake-curls
  $ port=1

Write a lockfile entry for [dep] that points at the fake URL +
checksum, with [(build dune)] so the synthesiser picks it up.

  $ make_lockpkg dep << EOF
  > (version 0.1)
  > (dune)
  > (source
  >  (fetch
  >   (url "http://0.0.0.0:$port")
  >   (checksum md5=$checksum)))
  > EOF

Set up the workspace package that depends on [dep].

  $ cat > main.ml << EOF
  > print_endline Dep.value
  > EOF
  $ cat > dune << EOF
  > (executable (name main) (libraries dep))
  > EOF
  $ cat > dune-project << EOF
  > (lang dune 3.25)
  > (package (name main) (depends dep))
  > EOF

Build through the mount: the outer dune drives the dep build using
the mounted unpacked tarball, then links main against it.

  $ dune exec ./main.exe 2>&1 | head -30
  from tarball

The pkg-mount synthesiser should have materialised a sibling context
for [dep]. The internal context name is [default.dep], with its build
dir under [_build/default.dep/].

  $ ls _build | grep -E '^default' | sort
  default
  default.dep
