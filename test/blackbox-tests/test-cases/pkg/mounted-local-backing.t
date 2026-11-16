A mounted package whose source is a local directory. R2 in PLAN.md: the mount
is to be backed by the directory on disk; today a snapshot of it is first
copied into _build/_fetch, from which the mount is copied again.

  $ make_lockdir
  $ cat > dune-project <<'EOF2'
  > (lang dune 3.25)
  > (package (name main) (allow_empty) (depends foo))
  > EOF2
  $ cat > dune <<'EOF2'
  > (dirs :standard \ _source _opaque)
  > (executable (name main) (libraries foo))
  > EOF2
  $ echo 'let () = print_endline Foo.message' > main.ml
  $ mkdir -p _source/sub _source/empty _source/_build _source/.git
  $ cat > _source/dune-project <<'EOF2'
  > (lang dune 3.25)
  > (package (name foo))
  > EOF2
  $ cat > _source/dune <<'EOF2'
  > (library (public_name foo))
  > (include stanzas.inc)
  > EOF2
  $ echo '(rule (target included) (action (write-file %{target} included)))' > _source/stanzas.inc
  $ echo 'let message = "original"' > _source/foo.ml
  $ echo '(rule (target out) (action (write-file %{target} sub)))' > _source/sub/dune
  $ mkdir _shared
  $ printf '#!/bin/sh\necho executable\n' > _shared/tool.sh
  $ chmod +x _shared/tool.sh
  $ ln -s ../_shared/tool.sh _source/tool.sh
  $ echo junk > _source/_build/junk.txt
  $ echo junk > _source/.git/config
  $ echo junk > '_source/.#editor.ml'
  $ make_lockpkg foo <<EOF2
  > (version 1.0)
  > (source (copy $PWD/_source))
  > (build (run false))
  > EOF2

Building a consumer does not need a snapshot of the source under _build/_fetch.

  $ dune build main.exe
  $ _build/default/main.exe
  original
  $ test ! -d _build/_fetch
  [1]

Editing a file on disk rebuilds the consumer.

  $ echo 'let message = "edited"' > _source/foo.ml
  $ dune build main.exe
  $ _build/default/main.exe
  edited

Adding and deleting files in a subdirectory are picked up.

  $ dune build _build/default/.pkg/foo/sub/out
  $ cat _build/default/.pkg/foo/sub/out
  sub
  $ rm _source/sub/dune
  $ dune build _build/default/.pkg/foo/sub/out 2>&1 | head -2
  Error: Don't know how to build _build/default/.pkg/foo/sub/out
  [1]
  $ echo 'let message = Extra.message' > _source/foo.ml
  $ echo 'let message = "added"' > _source/extra.ml
  $ dune build main.exe
  $ _build/default/main.exe
  added
  $ rm _source/extra.ml
  $ dune build main.exe 2>&1 | grep -c 'Unbound module'
  1
  [1]
  $ echo 'let message = "edited"' > _source/foo.ml

VCS and build directories and editor lock files of the source are not mounted.

  $ dune build main.exe
  $ test ! -e _build/default/.pkg/foo/_build
  $ test ! -e _build/default/.pkg/foo/.git
  $ dune build '_build/default/.pkg/foo/.#editor.ml' 2>&1 | head -1
  Error: Don't know how to build _build/default/.pkg/foo/.#editor.ml
  [1]

An included file is read from the source; its removal is reported.

  $ dune build _build/default/.pkg/foo/included
  $ cat _build/default/.pkg/foo/included
  included
  $ rm _source/stanzas.inc
  $ dune build main.exe 2>&1 | sed "s#$PWD#PWD#g"
  File "_build/default/.pkg/foo/dune", line 2, characters 0-21:
  Error: File _build/default/.pkg/foo/stanzas.inc doesn't exist.
  [1]
  $ echo '(rule (target included) (action (write-file %{target} included)))' > _source/stanzas.inc

An executable script keeps its mode in the mount.

  $ dune build _build/default/.pkg/foo/tool.sh
  $ _build/default/.pkg/foo/tool.sh
  executable
  $ test ! -L _build/default/.pkg/foo/tool.sh
  $ printf '#!/bin/sh\necho executable-edited\n' > _shared/tool.sh
  $ dune build _build/default/.pkg/foo/tool.sh
  $ _build/default/.pkg/foo/tool.sh
  executable-edited

An empty subdirectory is tolerated. It is not mounted, and an opaque recipe
does not see it either: only files are copied.

  $ dune build main.exe
  $ test ! -e _build/default/.pkg/foo/empty
  $ mkdir -p _opaque/empty
  $ echo content > _opaque/file
  $ make_lockpkg opaque <<EOF2
  > (version 1.0)
  > (source (copy $PWD/_opaque))
  > (build (run sh -c "ls; test ! -e empty"))
  > EOF2
  $ dune build _build/default/.pkg/opaque/_install 2>&1
  file

A missing local directory fails only the package that needs it, with the
lock-file location.

  $ make_lockpkg gone <<EOF2
  > (version 1.0)
  > (source (copy $PWD/_absent))
  > (build (run false))
  > EOF2
  $ cat >> dune <<'EOF2'
  > (rule (alias gone) (deps (package gone)) (action (echo unreachable)))
  > EOF2
  $ dune build main.exe
  $ dune build @gone 2>&1 | sed "s#$PWD#PWD#g" | dune_cmd delete ' *\^\^*$' | sed 's/characters [0-9-]*/characters X/'
  File "_build/_private/default/.lock/dune.lock/gone.pkg", line 2, characters X:
  2 | (source (copy PWD/_absent))
  Error:
  PWD/_absent
  does not exist
  [1]

Opaque recipes use the same direct backing. File links may point outside the
package source; their contents are copied, not the links. Recipe writes stay
inside the writable sandbox and do not change either origin.

  $ mkdir _recipe
  $ cd _recipe
  $ make_dune_project 3.25
  $ make_lockdir
  $ mkdir _source _shared
  $ echo original > _source/input.txt
  $ echo shared > _shared/input.txt
  $ ln -s ../_shared/input.txt _source/alias.txt
  $ make_lockpkg recipe <<EOF2
  > (version 1.0)
  > (source (copy $PWD/_source))
  > (build
  >  (progn
  >   (run cat input.txt alias.txt)
  >   (system "echo overwritten > input.txt")
  >   (write-file result built)
  >   (write-file recipe.install "share: [ \"result\" ]")))
  > EOF2
  $ dune build _build/default/.pkg/recipe/_install/share/recipe/result
  original
  shared
  $ cat _source/input.txt _shared/input.txt
  original
  shared
  $ test ! -L _build/default/.pkg/recipe/alias.txt
  $ test ! -d _build/_fetch
  [1]

Editing either local input rebuilds the recipe without changing its sources.

  $ echo edited > _source/input.txt
  $ echo shared-edited > _shared/input.txt
  $ dune build _build/default/.pkg/recipe/_install/share/recipe/result
  edited
  shared-edited
  $ cat _source/input.txt _shared/input.txt
  edited
  shared-edited
