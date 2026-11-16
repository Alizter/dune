Includes may ascend to a parent directory inside a mount, even above a nested
project root. They must not leave either the logical mount or its backing tree.

  $ make_lockdir
  $ make_dune_project 3.25
  $ mkdir -p _source/project/sub
  $ echo '(lang dune 3.25)' > _source/dune-project
  $ cat > _source/project/dune-project <<'EOF'
  > (lang dune 3.25)
  > (package (name foo))
  > EOF
  $ cat > _source/project/sub/dune <<'EOF'
  > (include ../../shared.inc)
  > EOF
  $ cat > _source/shared.inc <<'EOF'
  > (rule (target result) (action (write-file %{target} original)))
  > EOF
  $ cat > _source/dune <<'EOF'
  > (rule (target generated.inc) (action (copy shared.inc %{target})))
  > EOF

The same parent include works in the workspace. Mounting uses the prepared
version of the included file, without modifying the origin.

  $ (cd _source && dune build --root . project/sub/result)
  $ cat _source/_build/default/project/sub/result
  original
  $ make_lockpkg foo <<EOF
  > (version 1.0)
  > (source (copy $PWD/_source))
  > (build (run false))
  > EOF
  $ make_lockpkg_file foo shared.inc <<'EOF'
  > (rule (target result) (action (write-file %{target} prepared)))
  > EOF
  $ result=_build/default/.pkg/foo/project/sub/result
  $ dune build "$result"
  $ cat "$result"
  prepared
  $ cat _source/shared.inc
  (rule (target result) (action (write-file %{target} original)))

A missing parent include inside the mount still has its ordinary diagnostic.

  $ echo '(include ../../missing.inc)' > _source/project/sub/dune
  $ dune build "$result"
  File "_build/default/.pkg/foo/project/sub/dune", line 1, characters 0-27:
  Error: File _build/default/.pkg/foo/missing.inc doesn't exist.
  [1]

BUG: returning to the backing directory after ascending past its root currently
lets an include escape the logical mount. The rule is read from the prepared
source but named as though it belonged to a different mount.

  $ echo '(include ../../../source/shared.inc)' > _source/project/sub/dune
  $ dune build "$result"
  $ cat "$result"
  prepared

Conversely, returning to the logical mount after ascending past its root can
leave the backing directory. This must be rejected before testing existence.

  $ echo '(include ../../../foo/missing.inc)' > _source/project/sub/dune
  $ dune build "$result"
  File "_build/default/.pkg/foo/project/sub/dune", line 1, characters 0-34:
  Error: File _build/default/.pkg/foo/missing.inc doesn't exist.
  [1]

Includes emitted by an OCaml-syntax dune file must obey the same boundary.
BUG: the logical escape is accepted on this path too.

  $ cat > _source/project/sub/dune <<'EOF'
  > (* -*- tuareg -*- *)
  > let () = Jbuild_plugin.V1.send "(include ../../../source/shared.inc)"
  > EOF
  $ dune build "$result"
  $ cat "$result"
  prepared

Generated includes may also reach a parent inside the mount. The generated file
is built in the mount rather than read directly from the backing directory.

  $ echo '(dynamic_include ../../generated.inc)' > _source/project/sub/dune
  $ (cd _source && dune build --root . project/sub/result)
  $ cat _source/_build/default/project/sub/result
  original
  $ dune build "$result"
  $ cat "$result"
  prepared

BUG: a dynamic include can currently load a workspace file outside the mount.

  $ cat > outside.inc <<'EOF'
  > (rule (target result) (action (write-file %{target} workspace)))
  > EOF
  $ echo '(dynamic_include ../../../../outside.inc)' > _source/project/sub/dune
  $ dune build "$result"
  $ cat "$result"
  workspace

Include-loop diagnostics continue to use the logical paths inside the mount.

  $ echo '(include ../../shared.inc)' > _source/project/sub/dune
  $ make_lockpkg_file foo shared.inc <<'EOF'
  > (include project/sub/dune)
  > EOF
  $ dune build "$result"
  File "_build/default/.pkg/foo/project/sub/dune", line 1, characters 0-26:
  Error: Recursive inclusion of dune files detected:
  File _build/default/.pkg/foo/project/sub/dune is included from
  _build/default/.pkg/foo/shared.inc:1
     included from _build/default/.pkg/foo/project/sub/dune:1
  [1]
