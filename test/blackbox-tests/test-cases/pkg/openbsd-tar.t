Test that OpenBSD-style tar works when dune passes explicit flags (#10123).

Unlike GNU tar and BSD tar (libarchive), OpenBSD tar requires explicit
flags for compressed archives: -z for gzip, -j for bzip2, etc.

  $ make_lockdir

Set up a fake tar that behaves like OpenBSD tar:
- Fails on --version (not supported)
- Requires explicit decompression flags

  $ mkdir -p .binaries
  $ cat > .binaries/openbsd-tar << 'EOF'
  > #!/usr/bin/env sh
  > # Parse flags - OpenBSD tar doesn't support long options
  > has_z=false
  > has_j=false
  > archive=""
  > target=""
  > for arg in "$@"; do
  >   case "$arg" in
  >     --*) echo "tar: unknown option -- -" >&2; exit 1 ;;
  >     -*z*) has_z=true ;;
  >     -*j*) has_j=true ;;
  >   esac
  > done
  > # Find -f and -C arguments
  > while [ $# -gt 0 ]; do
  >   case "$1" in
  >     -f) archive="$2"; shift ;;
  >     -C) target="$2"; shift ;;
  >   esac
  >   shift
  > done
  > # Require correct flag for compressed archives
  > case "$archive" in
  >   *.tar.gz|*.tgz)
  >     $has_z || { echo "tar: input compressed with gzip; use the -z option to decompress it" >&2; exit 1; }
  >     ;;
  >   *.tar.bz2|*.tbz)
  >     $has_j || { echo "tar: input compressed with bzip2; use the -j option to decompress it" >&2; exit 1; }
  >     ;;
  > esac
  > # Success - create fake extracted content
  > mkdir -p "$target/pkg-content"
  > echo "extracted" > "$target/pkg-content/file.txt"
  > EOF
  $ chmod +x .binaries/openbsd-tar

Set up fake PATH with only our OpenBSD-style tar:

  $ mkdir -p .fakebin
  $ ln -s $(which dune) .fakebin/dune
  $ ln -s $(which sh) .fakebin/sh
  $ ln -s $(which mkdir) .fakebin/mkdir
  $ ln -s $(which echo) .fakebin/echo
  $ ln -s $(which grep) .fakebin/grep
  $ ln -s ../.binaries/openbsd-tar .fakebin/tar

Helper to show tar extract args from trace (filters to -x calls only):

  $ tar_extract_args() {
  >   dune trace cat | jq -c 'include "dune"; processes
  >     | select(.args.prog | contains("tar"))
  >     | select(.args.process_args | index("-x"))
  >     | .args.process_args
  >     | map(if (startswith("/") or startswith("_build")) then "PATH" else . end)'
  > }

Test with a .tar.gz file:

  $ echo "fake tarball" > test.tar.gz

  $ make_lockpkg foo <<EOF
  > (source
  >  (fetch
  >   (url "file://$PWD/test.tar.gz")))
  > (version dev)
  > EOF

  $ PATH=.fakebin build_pkg foo
  tar: unknown option -- -

Verify that -z flag was passed:

  $ tar_extract_args
  ["-x","-z","-f","PATH","-C","PATH"]

Test with a .tbz file (bzip2 compressed):

  $ echo "fake tarball" > test.tbz

  $ make_lockpkg bar <<EOF
  > (source
  >  (fetch
  >   (url "file://$PWD/test.tbz")))
  > (version dev)
  > EOF

  $ PATH=.fakebin build_pkg bar
  tar: unknown option -- -

Verify that -j flag was passed:

  $ tar_extract_args
  ["-x","-j","-f","PATH","-C","PATH"]

Test with a .tar.xz file - should error with helpful message since OpenBSD tar
doesn't support XZ:

  $ echo "fake tarball" > test.tar.xz

  $ make_lockpkg xzpkg <<EOF
  > (source
  >  (fetch
  >   (url "file://$PWD/test.tar.xz")))
  > (version dev)
  > EOF

  $ PATH=.fakebin build_pkg xzpkg 2>&1 | dune_cmd delete '^File |^ *[0-9]+ \||^ +\^'
  tar: unknown option -- -
  Error: Cannot extract 'test.tar.xz'
  The detected tar does not support XZ decompression. XZ archives require GNU
  tar or libarchive.
  Hint: Install GNU tar or bsdtar (libarchive) for XZ support.
  [1]

Test with a .tar.lzma file - should error with helpful message since OpenBSD tar
doesn't support LZMA:

  $ echo "fake tarball" > test.tar.lzma

  $ make_lockpkg lzmapkg <<EOF
  > (source
  >  (fetch
  >   (url "file://$PWD/test.tar.lzma")))
  > (version dev)
  > EOF

  $ PATH=.fakebin build_pkg lzmapkg 2>&1 | dune_cmd delete '^File |^ *[0-9]+ \||^ +\^'
  tar: unknown option -- -
  Error: Cannot extract 'test.tar.lzma'
  The detected tar does not support LZMA decompression. LZMA archives require
  GNU tar or libarchive.
  Hint: Install GNU tar or bsdtar (libarchive) for LZMA support.
  [1]
