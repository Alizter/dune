Lock packages that share one source archive are loaded once, while nested Dune
projects retain their own package identity and contribute libraries to the same
workspace build.

  $ export DUNE_CACHE_ROOT="$PWD/.cache"
  $ cat > dune-workspace <<'EOF'
  > (lang dune 3.20)
  > (pkg enabled)
  > EOF
  $ cat > dune-project <<'EOF'
  > (lang dune 3.20)
  > (package
  >  (name main)
  >  (depends foo bar))
  > EOF
  $ cat > dune <<'EOF'
  > (executable
  >  (name main)
  >  (libraries foo bar))
  > EOF
  $ cat > main.ml <<'EOF'
  > let () = Printf.printf "%s/%s\n" Foo.message Bar.message
  > EOF

  $ mkdir -p shared/sub shared/invalid.t
  $ cat > shared/dune-project <<'EOF'
  > (lang dune 3.20)
  > (package (name foo))
  > EOF
  $ cat > shared/dune <<'EOF'
  > (library
  >  (name foo)
  >  (public_name foo))
  > (cram
  >  (applies_to :whole_subtree))
  > EOF
  $ cat > shared/foo.ml <<'EOF'
  > let message = "root-project"
  > EOF

A Cram test directory may contain intentionally invalid Dune projects. It is test
data and must be masked before mounted project discovery attempts to decode it.

  $ cat > shared/invalid.t/dune-project <<'EOF'
  > (lang dune 3.20)
  > (lang dune 3.20)
  > EOF
  $ cat > shared/sub/dune-project <<'EOF'
  > (lang dune 3.20)
  > (package (name bar))
  > EOF
  $ cat > shared/sub/dune <<'EOF'
  > (library
  >  (name bar)
  >  (public_name bar))
  > EOF
  $ cat > shared/sub/bar.ml <<'EOF'
  > let message = "nested-project"
  > EOF
  $ tar cf shared.tar shared
  $ rm -rf shared

  $ checksum=$(md5sum shared.tar | cut -f1 -d' ')
  $ make_lockdir
  $ make_lockpkg foo <<EOF
  > (version 1.0)
  > (source
  >  (fetch
  >   (url file://$PWD/shared.tar)
  >   (checksum md5=$checksum)))
  > (build (run dune build @install))
  > EOF
  $ make_lockpkg bar <<EOF
  > (version 1.0)
  > (source
  >  (fetch
  >   (url file://$PWD/shared.tar)
  >   (checksum md5=$checksum)))
  > (build (run dune build @install))
  > EOF

  $ real_dune="$(command -v dune)"
  $ fake_bin="$TMPDIR/mounted-dune-package-projects-bin"
  $ rm -rf "$fake_bin"
  $ mkdir "$fake_bin"
  $ cat > "$fake_bin/dune" <<EOF
  > #!/bin/sh
  > echo nested-dune > "$PWD/nested-dune"
  > exit 99
  > EOF
  $ chmod +x "$fake_bin/dune"
  $ PATH="$fake_bin:$PATH" "$real_dune" build ./main.exe --display quiet
  $ ./_build/default/main.exe
  root-project/nested-project
  $ test ! -e nested-dune && echo no-nested-dune
  no-nested-dune
  $ test ! -d _build/_private/default/.pkg && echo no-old-package-rules
  no-old-package-rules

The shared transport has one build-backed fetch target and two lock identities
with distinct output roots. Package masking selects the relevant package from
each mounted view, while the nested library retains its project-relative output
directory.

  $ test "$(find _build/_fetch -type d -name dir | wc -l)" -eq 1 && echo one-source-target
  one-source-target
  $ test ! -e "$DUNE_CACHE_ROOT/pkg-sources" && echo no-external-source-store
  no-external-source-store
  $ test "$(find _build/_default+lockfile/pkg -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 2 && echo two-artifact-roots
  two-artifact-roots
  $ foo_root=_build/_default+lockfile/pkg/foo
  $ bar_root=_build/_default+lockfile/pkg/bar
  $ test -f "$foo_root/foo.cmxa" && test -f "$bar_root/sub/bar.cmxa" && echo nested-artifacts
  nested-artifacts
  $ test ! -e "$foo_root/sub/bar.cmxa" && test ! -e "$bar_root/foo.cmxa" && echo package-masks
  package-masks

A mounted package may form one module group from files in nested build-backed
source directories. Group discovery must use the rules-side source tree rather
than the workspace-only engine source tree.

  $ mkdir include-subdirs
  $ cd include-subdirs
  $ cat > dune-workspace <<'EOF'
  > (lang dune 3.20)
  > (pkg enabled)
  > EOF
  $ cat > dune-project <<'EOF'
  > (lang dune 3.20)
  > (package
  >  (name main)
  >  (depends grouped))
  > EOF
  $ cat > dune <<'EOF'
  > (executable
  >  (name main)
  >  (libraries grouped))
  > EOF
  $ echo 'let () = print_endline Grouped.message' > main.ml

  $ mkdir -p grouped/src/nested
  $ cat > grouped/dune-project <<'EOF'
  > (lang dune 3.20)
  > (package (name grouped))
  > EOF
  $ cat > grouped/src/dune <<'EOF'
  > (include_subdirs unqualified)
  > (library
  >  (name grouped)
  >  (public_name grouped))
  > EOF
  $ echo 'let message = Message.message' > grouped/src/grouped.ml
  $ echo 'let message = "mounted include_subdirs"' > grouped/src/nested/message.ml
  $ tar cf grouped.tar grouped
  $ rm -rf grouped

  $ make_lockdir
  $ make_lockpkg grouped <<EOF
  > (version 1.0)
  > (depends dune)
  > (source
  >  (fetch
  >   (url file://$PWD/grouped.tar)
  >   (checksum md5=$(md5sum grouped.tar | cut -f1 -d' '))))
  > (build (run dune build -p %{pkg-self:name} -j %{jobs}))
  > EOF

  $ "$real_dune" build ./main.exe --display quiet
  $ ./_build/default/main.exe
  mounted include_subdirs
  $ grouped_root=_build/_default+lockfile/pkg/grouped
  $ test -n "$(find "$grouped_root/src/.grouped.objs" -name '*Message*.cmx' -print -quit)" && echo nested-module-artifact
  nested-module-artifact
  $ test ! -e _build/_private/default/.pkg/grouped.1.0-* && echo no-old-package-rules
  no-old-package-rules

A vendored project bundled in a mounted package remains visible to the owning
package even though the vendored project's package is not selected from the
lock directory.

  $ mkdir vendored-project
  $ cd vendored-project
  $ cat > dune-workspace <<'EOF'
  > (lang dune 3.20)
  > (pkg enabled)
  > EOF
  $ cat > dune-project <<'EOF'
  > (lang dune 3.20)
  > (package
  >  (name main)
  >  (depends bundle))
  > EOF
  $ cat > dune <<'EOF'
  > (executable
  >  (name main)
  >  (libraries bundle))
  > EOF
  $ echo 'let () = print_endline Bundle.message' > main.ml

  $ mkdir -p bundle/vendor/src
  $ cat > bundle/dune-project <<'EOF'
  > (lang dune 3.20)
  > (package (name bundle))
  > EOF
  $ cat > bundle/dune <<'EOF'
  > (vendored_dirs vendor)
  > (library
  >  (name bundle)
  >  (public_name bundle)
  >  (libraries vendored_support))
  > EOF
  $ echo 'let message = Vendored_support.message' > bundle/bundle.ml
  $ cat > bundle/vendor/dune-project <<'EOF'
  > (lang dune 3.20)
  > (package (name vendored_support))
  > EOF
  $ cat > bundle/vendor/src/dune <<'EOF'
  > (library
  >  (name vendored_support)
  >  (public_name vendored_support))
  > EOF
  $ echo 'let message = "mounted vendored project"' > bundle/vendor/src/vendored_support.ml
  $ tar cf bundle.tar bundle
  $ rm -rf bundle

  $ make_lockdir
  $ make_lockpkg bundle <<EOF
  > (version 1.0)
  > (depends dune)
  > (source
  >  (fetch
  >   (url file://$PWD/bundle.tar)
  >   (checksum md5=$(md5sum bundle.tar | cut -f1 -d' '))))
  > (build (run dune build -p %{pkg-self:name} -j %{jobs}))
  > EOF

  $ "$real_dune" build ./main.exe --display quiet
  $ ./_build/default/main.exe
  mounted vendored project

Each selected package view of a shared archive owns its own copy of a bundled
auxiliary library.

  $ mkdir ../shared-auxiliary-project
  $ cd ../shared-auxiliary-project
  $ cat > dune-workspace <<'EOF'
  > (lang dune 3.20)
  > (pkg enabled)
  > EOF
  $ cat > dune-project <<'EOF'
  > (lang dune 3.20)
  > (package
  >  (name main)
  >  (depends left right))
  > EOF
  $ cat > dune <<'EOF'
  > (rule
  >  (targets left.output right.output)
  >  (action
  >   (progn
  >    (with-stdout-to left.output (run %{bin:left-tool}))
  >    (with-stdout-to right.output (run %{bin:right-tool})))))
  > EOF

  $ mkdir -p shared/vendor/src
  $ cat > shared/dune-project <<'EOF'
  > (lang dune 3.20)
  > (package (name left))
  > (package (name right))
  > EOF
  $ cat > shared/dune <<'EOF'
  > (library
  >  (name left)
  >  (public_name left)
  >  (modules left)
  >  (libraries vendored_support))
  > (library
  >  (name right)
  >  (public_name right)
  >  (modules right)
  >  (libraries vendored_support))
  > (executable
  >  (name left_tool)
  >  (public_name left-tool)
  >  (package left)
  >  (modules left_tool)
  >  (libraries vendored_support))
  > (executable
  >  (name right_tool)
  >  (public_name right-tool)
  >  (package right)
  >  (modules right_tool)
  >  (libraries vendored_support))
  > EOF
  $ echo 'let message = Vendored_support.message' > shared/left.ml
  $ echo 'let message = Vendored_support.message' > shared/right.ml
  $ echo 'let () = print_endline (Vendored_support.message ^ "/left")' > shared/left_tool.ml
  $ echo 'let () = print_endline (Vendored_support.message ^ "/right")' > shared/right_tool.ml
  $ cat > shared/vendor/dune-project <<'EOF'
  > (lang dune 3.20)
  > (package (name vendored_support))
  > (package (name unused_support))
  > EOF
  $ cat > shared/vendor/src/dune <<'EOF'
  > (library
  >  (name vendored_support)
  >  (public_name vendored_support)
  >  (modules vendored_support)
  >  (libraries unix))
  > (library
  >  (name unused_support)
  >  (public_name unused_support)
  >  (modules unused_support)
  >  (libraries unavailable))
  > EOF
  $ cat > shared/vendor/src/vendored_support.ml <<'EOF'
  > let message =
  >   let (_ : Unix.file_descr) = Unix.stdin in
  >   "shared auxiliary"
  > EOF
  $ echo 'let unused = ()' > shared/vendor/src/unused_support.ml
  $ tar cf shared.tar shared
  $ rm -rf shared

  $ checksum=$(md5sum shared.tar | cut -f1 -d' ')
  $ make_lockdir
  $ make_lockpkg left <<EOF
  > (version 1.0)
  > (depends dune)
  > (source
  >  (fetch
  >   (url file://$PWD/shared.tar)
  >   (checksum md5=$checksum)))
  > (build (run dune build -p %{pkg-self:name} -j %{jobs}))
  > EOF
  $ make_lockpkg right <<EOF
  > (version 1.0)
  > (depends dune)
  > (source
  >  (fetch
  >   (url file://$PWD/shared.tar)
  >   (checksum md5=$checksum)))
  > (build (run dune build -p %{pkg-self:name} -j %{jobs}))
  > EOF

  $ "$real_dune" build left.output right.output --display quiet
  $ cat _build/default/left.output _build/default/right.output
  shared auxiliary/left
  shared auxiliary/right
  $ left_root=_build/_default+lockfile/pkg/left
  $ right_root=_build/_default+lockfile/pkg/right
  $ test -f "$left_root/vendor/src/vendored_support.cmxa" && test -f "$right_root/vendor/src/vendored_support.cmxa" && echo separately-owned-auxiliary-artifacts
  separately-owned-auxiliary-artifacts

Selected libraries' metadata includes the owner-local auxiliary library it
requires, so external build systems can resolve the private findlib package.

  $ "$real_dune" build "$left_root/META.left" --display quiet
  $ grep -c 'package "__private__"' "$left_root/META.left"
  1
  $ grep -c 'package "vendored_support"' "$left_root/META.left"
  1
  $ grep 'requires = "left.__private__.vendored_support"' "$left_root/META.left"
  requires = "left.__private__.vendored_support"
  $ grep -c unused_support "$left_root/META.left" || true
  0
  $ "$real_dune" build @pkg-install --display quiet
  $ left_layout=$(echo _build/install/default/.packages/*/lib/left)
  $ right_layout=$(echo _build/install/default/.packages/*/lib/right)
  $ test -L "$left_layout/__private__/vendored_support/vendored_support.cmxa" && test -L "$right_layout/__private__/vendored_support/vendored_support.cmxa" && echo private-layout-artifacts
  private-layout-artifacts
