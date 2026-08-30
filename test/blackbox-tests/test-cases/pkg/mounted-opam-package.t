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
  >  (depends native)
  >  (allow_empty))
  > EOF

  $ mkdir opaque
  $ echo primary > opaque/input.txt
  $ echo extra > extra.txt
  $ echo source-less-extra > source-less-extra.txt

The native package consumes an installed file from the synthetic package. This
keeps the native-to-Opam edge in the ordinary package dependency graph.

  $ mkdir native
  $ cat > native/dune-project <<'EOF'
  > (lang dune 3.25)
  > (package (name native))
  > EOF
  $ cat > native/dune <<'EOF'
  > (rule
  >  (target from-opaque.txt)
  >  (deps %{pkg:opaque:share:built.txt})
  >  (action (copy %{deps} %{target})))
  > (install
  >  (package native)
  >  (section share)
  >  (files from-opaque.txt))
  > EOF
  $ tar cf native.tar native
  $ rm -rf native

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
  $ make_lockpkg native <<EOF
  > (version 1.0)
  > (depends opaque)
  > (source (copy $PWD/native.tar))
  > (build (run dune build @install))
  > EOF
  $ make_lockpkg source-less <<EOF
  > (version 1.0)
  > (extra_sources (extra.txt (copy $PWD/source-less-extra.txt)))
  > (build (system "cat from-files extra.txt > built.txt"))
  > (install
  >  (progn
  >   (run mkdir -p %{share}/source-less)
  >   (run cp built.txt %{share}/source-less/built.txt)))
  > EOF
  $ make_lockpkg_file source-less from-files <<'EOF'
  > source-less-files
  > EOF
  $ make_lockpkg transition <<'EOF'
  > (version 1.0)
  > (depends source-less)
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
  $ native_root=$(echo _build/_default+lockfile/pkg/native.1.0-*)
  $ cat "$native_root/from-opaque.txt"
  primary
  files
  extra

A source-less package starts with an empty sandbox working directory and uses
the same synthetic target and cookie protocol without a fetch target.

  $ source_less_root=$(echo _build/_default+lockfile/pkg/source-less.1.0-*)
  $ source_less_target="$source_less_root/.opam/source-less/target"
  $ cat "$source_less_target/share/source-less/built.txt"
  source-less-files
  source-less-extra
  $ test -f "$source_less_target/cookie" && echo source-less-cookie
  source-less-cookie
  $ test ! -e "$source_less_root/.opam/source-less/source" && echo no-primary-source-target
  no-primary-source-target
  $ transition_root=$(echo _build/_default+lockfile/pkg/transition.1.0-*)
  $ test -f "$transition_root/.opam/transition/target/cookie" && echo empty-transition-cookie
  empty-transition-cookie
  $ test ! -e "$transition_root/.opam/transition/source" && echo no-transition-source-target
  no-transition-source-target

  $ test ! -d _build/_private/default/.pkg && echo no-legacy-package-target
  no-legacy-package-target

The build recipe and overlays mutate only the copy sandbox. They do not become
part of the primary source target.

  $ source_root=$(dirname "$(find _build/_fetch -type f -name input.txt)")
  $ test -f "$source_root/input.txt" && echo primary-source
  primary-source
  $ test ! -e "$source_root/from-files" && test ! -e "$source_root/extra.txt" && test ! -e "$source_root/built.txt" && echo source-unchanged
  source-unchanged
