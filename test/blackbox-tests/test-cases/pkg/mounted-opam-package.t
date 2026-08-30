A lock package without Dune files is represented by a synthetic opam stanza in
the alternate package context. Its immutable primary source remains separate
from build-time overlays and installed artifacts.

  $ cat > dune-workspace <<'EOF'
  > (lang dune 3.20)
  > (pkg enabled)
  > EOF
  $ cat > dune-project <<'EOF'
  > (lang dune 3.20)
  > (package
  >  (name main)
  >  (depends opaque)
  >  (allow_empty))
  > EOF

  $ mkdir opaque
  $ echo primary > opaque/input.txt
  $ echo extra > extra.txt
  $ echo source-less-extra > source-less-extra.txt

  $ make_lockdir
  $ make_lockpkg opaque <<EOF
  > (version 1.0)
  > (source (copy $PWD/opaque))
  > (extra_sources (extra.txt (copy $PWD/extra.txt)))
  > (build (system "cat input.txt from-files extra.txt > built.txt"))
  > (install
  >  (progn
  >   (run mkdir -p %{share}/opaque)
  >   (run cp built.txt %{share}/opaque/built.txt)))
  > EOF
  $ make_lockpkg_file opaque from-files <<'EOF'
  > files
  > EOF

  $ dune build @pkg-install

The synthetic stanza owns the same target layout as a user-authored opam
stanza, rooted beneath the exact package artifact directory.

  $ artifact_root=$(echo _build/_default+lockfile/pkg/opaque.1.0-*)
  $ target="$artifact_root/.opam/opaque/target"
  $ cat "$target/share/opaque/built.txt"
  primary
  files
  extra
  $ test -f "$target/cookie" && echo cookie
  cookie
  $ test ! -d _build/_private/default/.pkg && echo no-legacy-package-target
  no-legacy-package-target

The build recipe and overlays mutate only the copy sandbox. They do not become
part of the primary source target.

  $ source_root=$(find _build/_fetch -type d -name dir)
  $ test -f "$source_root/input.txt" && echo primary-source
  primary-source
  $ test ! -e "$source_root/from-files" && test ! -e "$source_root/extra.txt" && test ! -e "$source_root/built.txt" && echo source-unchanged
  source-unchanged
