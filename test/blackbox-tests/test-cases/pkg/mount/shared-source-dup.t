When two packages share the same upstream source (a common shape in
opam repositories — multiple installable packages built from one
release tarball), the lockfile records them as separate entries but
both [(fetch ...)] sources reference the same URL+checksum. The
pkg-mount synthesiser today materialises a sibling context PER
PACKAGE, so the shared source tree is unpacked twice under
[_build/_private/default/.pkg/<digest>/source/], each interpreted as
an independent workspace by [Dune_load].

That makes the package declarations in the shared dune-project visible
twice — once per sibling context. The outer build sees [(package
(name a))] and [(package (name b))] declared in two different
locations and errors out, because [Dune_load.packages] enforces a
single declaration per package across the contexts it merges.

This test pins the duplication so a future fix (source-tree dedup
keyed on URL+checksum, or filtering each sibling's source tree by the
single package the lockfile entry declares) flips its output from the
"defined more than once" error to a successful build.

  $ make_lockdir

Build one tarball that ships dune-project declaring two packages [a]
and [b], with separate libraries for each.

  $ mkdir _sources
  $ cat > _sources/dune-project << EOF
  > (lang dune 3.25)
  > (package (name a))
  > (package (name b))
  > EOF
  $ mkdir _sources/a _sources/b
  $ cat > _sources/a/dune << EOF
  > (library (public_name a))
  > EOF
  $ cat > _sources/a/a.ml << EOF
  > let value = "a"
  > EOF
  $ cat > _sources/b/dune << EOF
  > (library (public_name b))
  > EOF
  $ cat > _sources/b/b.ml << EOF
  > let value = "b"
  > EOF
  $ tar cf shared.tar _sources
  $ checksum=$(md5sum shared.tar | awk '{ print $1 }')
  $ echo shared.tar > fake-curls
  $ port=1

Two lockfile entries — one per published package — both pointing at
the same fetch URL+checksum. Both [(dune)], so the synthesiser
materialises a sibling context for each.

  $ make_lockpkg a << EOF
  > (version 0.1)
  > (dune)
  > (source
  >  (fetch
  >   (url "http://0.0.0.0:$port")
  >   (checksum md5=$checksum)))
  > EOF

  $ make_lockpkg b << EOF
  > (version 0.1)
  > (dune)
  > (source
  >  (fetch
  >   (url "http://0.0.0.0:$port")
  >   (checksum md5=$checksum)))
  > EOF

Workspace project depends on both [a] and [b].

  $ cat > main.ml << EOF
  > print_endline (A.value ^ B.value)
  > EOF
  $ cat > dune << EOF
  > (executable (name main) (libraries a b))
  > EOF
  $ cat > dune-project << EOF
  > (lang dune 3.25)
  > (package (name main) (depends a b))
  > EOF

The expected end state is that the build succeeds and prints [ab].
Today it fails because [a] and [b] are seen twice — once from
[_build/default.a/]'s view of the shared tarball, and once from
[_build/default.b/]'s view of the same bytes (re-fetched into a
separate [<digest>/source/] under [Paths.make]'s per-pkg keying).

  $ dune exec ./main.exe 2>&1 | head -20
  ab

Both sibling contexts materialise — separate copies of the shared
source under different pkg-digests.

  $ ls _build | grep -E '^default' | sort
  default
  default.a
  default.b

The source tree IS duplicated under each pkg's [_build/_private]
path: the same tarball gets unpacked once per pkg-digest.

  $ find _build/_private/default/.pkg -maxdepth 3 -name source -type d | sort | wc -l
  2

And each unpacked source tree carries the full dune-project declaring
both [a] and [b], so each sibling context has a chance to see the
duplicates.

  $ find _build/_private/default/.pkg -maxdepth 4 -name dune-project | sort | wc -l
  2
