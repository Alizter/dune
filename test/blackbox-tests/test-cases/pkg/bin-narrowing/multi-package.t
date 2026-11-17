Per-owner binary visibility is independent of the provider's backend. Each
owner sees its declared tool, not the other owner's tool; an owner with no
dependencies sees neither. Exercise workspace and mounted requesters against
the same native/opaque providers.

Create two distinct tools with renamed installation entries and shared
requester rules. Lookup must use the installed name, not the source basename.

  $ mkdir -p _providers _requesters native opaque
  $ (set -eu
  >  for owner in a b; do
  >    source="_providers/tool-$owner"
  >    mkdir -p "$source" "_requesters/$owner"
  >    printf '(lang dune 3.25)\n(package (name tool-%s))\n' "$owner" \
  >      > "$source/dune-project"
  >    printf '(install (section bin) (files (tool-%s.sh as bin-%s)))\n' \
  >      "$owner" "$owner" > "$source/dune"
  >    printf '#!/bin/sh\necho from-%s\n' "$owner" > "$source/tool-$owner.sh"
  >    chmod +x "$source/tool-$owner.sh"
  >    cat > "_requesters/$owner/dune" <<EOF
  > (rule
  >  (target available)
  >  (action
  >   (with-stdout-to %{target}
  >    (echo %{bin-available:bin-a} %{bin-available:bin-b}))))
  > (rule
  >  (target pform-output)
  >  (action (with-stdout-to %{target} (run %{bin:bin-$owner}))))
  > (rule
  >  (target literal-output)
  >  (action (with-stdout-to %{target} (run bin-$owner))))
  > (rule
  >  (target path)
  >  (action (with-stdout-to %{target} (bash "echo \$PATH"))))
  > EOF
  >  done
  >  mkdir _requesters/denied
  >  cp _requesters/a/dune _requesters/denied/dune
  > )
  $ cat > _requesters/dune-project <<'EOF'
  > (lang dune 3.25)
  > (package (name pkg-a) (allow_empty) (dir a) (depends tool-a))
  > (package (name pkg-b) (allow_empty) (dir b) (depends tool-b))
  > (package (name denied) (allow_empty) (dir denied))
  > EOF
  $ mkdir _mounted
  $ cp -R _requesters/. _mounted/
  $ cat > _mounted/dune-project <<'EOF'
  > (lang dune 3.25)
  > (package (name mounted-a) (dir a) (depends tool-a))
  > (package (name mounted-b) (dir b) (depends tool-b))
  > (package (name mounted-denied) (dir denied))
  > EOF
  $ make_case() (
  >   set -eu
  >   local backend="$1"
  >   cp -R _requesters/. "$backend/"
  >   cd "$backend"
  >   make_lockdir
  >   for owner in a b; do
  >     make_dune_source_lockpkg "$backend" "tool-$owner" \
  >       "$PWD/../_providers/tool-$owner"
  >     make_dune_source_lockpkg native "mounted-$owner" "$PWD/../_mounted"
  >     printf '(depends tool-%s)\n' "$owner" \
  >       | append_to_lockpkg "mounted-$owner"
  >   done
  >   make_dune_source_lockpkg native mounted-denied "$PWD/../_mounted"
  > )
  $ make_case native
  $ make_case opaque

First build only owner a. Looking up its declared tool must not materialise
the unrelated tool: inspect the native artifact, not its unused install prefix.

  $ (cd native && dune build a/available a/pform-output a/literal-output)
  $ cat native/_build/default/a/available
  true false
  $ cat native/_build/default/a/{pform-output,literal-output}
  from-a
  from-a
  $ test -f native/_build/default/.pkg/tool-a/tool-a.sh
  $ test ! -e native/_build/default/.pkg/tool-b/tool-b.sh
  $ test ! -e native/_build/default/.pkg/tool-a/_install/cookie

The opaque case has the same cold lookup, but cookie existence is the
load-bearing build check for this backend.

  $ (cd opaque && dune build a/available a/pform-output a/literal-output)
  $ cat opaque/_build/default/a/available
  true false
  $ cat opaque/_build/default/a/{pform-output,literal-output}
  from-a
  from-a
  $ test ! -e opaque/_build/default/.pkg/tool-b/_install/cookie

The reciprocal owner sees b, not a. Both providers are now built, so later
denials cannot pass just because their program has not been built yet.

  $ (cd native && dune build b/available b/pform-output b/literal-output)
  $ cat native/_build/default/b/available
  false true
  $ cat native/_build/default/b/{pform-output,literal-output}
  from-b
  from-b
  $ (cd opaque && dune build b/available b/pform-output b/literal-output)
  $ cat opaque/_build/default/b/available
  false true
  $ cat opaque/_build/default/b/{pform-output,literal-output}
  from-b
  from-b
  $ cat opaque/_build/default/.pkg/tool-{a,b}/_install/opaque-recipe
  opaque
  opaque
  $ test -f opaque/_build/default/.pkg/tool-a/_install/cookie
  $ test -f opaque/_build/default/.pkg/tool-b/_install/cookie
  $ test ! -e native/_build/default/.pkg/tool-b/_install/cookie

Keep the opaque per-owner PATH discriminator: each action receives only its
declared provider's install bin directory. Do not assume an equivalent native
install-prefix layout.

  $ cd opaque
  $ dune build a/path b/path
  $ env_added "$(cat _build/default/a/path)" "$PATH" | censor
  $PWD/_build/default/.pkg/tool-a/_install/bin
  $ env_added "$(cat _build/default/b/path)" "$PATH" | censor
  $PWD/_build/default/.pkg/tool-b/_install/bin
  $ cd ..

Mounted requesters use their lock metadata, not the workspace owner's
dependencies. Both reciprocal owners must still resolve their own tool.

  $ mounted_a=_build/default/.pkg/mounted-a/a
  $ mounted_b=_build/default/.pkg/mounted-b/b
  $ mounted_denied=_build/default/.pkg/mounted-denied/denied
  $ (cd native &&
  >  dune build "$mounted_a"/{available,pform-output,literal-output} \
  >   "$mounted_b"/{available,pform-output,literal-output})
  $ cat native/_build/default/.pkg/mounted-a/a/available
  true false
  $ cat native/_build/default/.pkg/mounted-b/b/available
  false true
  $ cat native/_build/default/.pkg/mounted-a/a/{pform-output,literal-output}
  from-a
  from-a
  $ cat native/_build/default/.pkg/mounted-b/b/{pform-output,literal-output}
  from-b
  from-b

  $ (cd opaque &&
  >  dune build "$mounted_a"/{available,pform-output,literal-output} \
  >   "$mounted_b"/{available,pform-output,literal-output})
  $ cat opaque/_build/default/.pkg/mounted-a/a/available
  true false
  $ cat opaque/_build/default/.pkg/mounted-b/b/available
  false true
  $ cat opaque/_build/default/.pkg/mounted-a/a/{pform-output,literal-output}
  from-a
  from-a
  $ cat opaque/_build/default/.pkg/mounted-b/b/{pform-output,literal-output}
  from-b
  from-b

An empty-dependency owner cannot discover or run either warmed provider.
Keep the failing pform and literal lookups separate, including the logical
mounted paths in their diagnostics.

  $ (cd native && dune build denied/available)
  $ cat native/_build/default/denied/available
  false false
  $ (cd native && dune build denied/pform-output)
  File "denied/dune", line 8, characters 40-52:
  8 |  (action (with-stdout-to %{target} (run %{bin:bin-a}))))
                                              ^^^^^^^^^^^^
  Error: Program bin-a not found in the tree or in PATH
   (context: default)
  Hint: add a dependency on the package installing "bin-a" to this package
  [1]
  $ (cd native && dune build denied/literal-output)
  File "denied/dune", line 11, characters 40-45:
  11 |  (action (with-stdout-to %{target} (run bin-a))))
                                               ^^^^^
  Error: Program bin-a not found in the tree or in PATH
   (context: default)
  Hint: add a dependency on the package installing "bin-a" to this package
  [1]
  $ (cd native && dune build "$mounted_denied/available")
  $ cat native/_build/default/.pkg/mounted-denied/denied/available
  false false
  $ (cd native && dune build "$mounted_denied/pform-output")
  File "_build/default/.pkg/mounted-denied/denied/dune", line 8, characters 40-52:
  Error: Program bin-a not found in the tree or in PATH
   (context: default)
  Hint: add a dependency on the package installing "bin-a" to this package
  [1]
  $ (cd native && dune build "$mounted_denied/literal-output")
  File "_build/default/.pkg/mounted-denied/denied/dune", line 11, characters 40-45:
  Error: Program bin-a not found in the tree or in PATH
   (context: default)
  Hint: add a dependency on the package installing "bin-a" to this package
  [1]

  $ (cd opaque && dune build denied/available)
  $ cat opaque/_build/default/denied/available
  false false
  $ (cd opaque && dune build denied/pform-output)
  File "denied/dune", line 8, characters 40-52:
  8 |  (action (with-stdout-to %{target} (run %{bin:bin-a}))))
                                              ^^^^^^^^^^^^
  Error: Program bin-a not found in the tree or in PATH
   (context: default)
  Hint: add a dependency on the package installing "bin-a" to this package
  [1]
  $ (cd opaque && dune build denied/literal-output)
  File "denied/dune", line 11, characters 40-45:
  11 |  (action (with-stdout-to %{target} (run bin-a))))
                                               ^^^^^
  Error: Program bin-a not found in the tree or in PATH
   (context: default)
  Hint: add a dependency on the package installing "bin-a" to this package
  [1]
  $ (cd opaque && dune build "$mounted_denied/available")
  $ cat opaque/_build/default/.pkg/mounted-denied/denied/available
  false false
  $ (cd opaque && dune build "$mounted_denied/pform-output")
  File "_build/default/.pkg/mounted-denied/denied/dune", line 8, characters 40-52:
  Error: Program bin-a not found in the tree or in PATH
   (context: default)
  Hint: add a dependency on the package installing "bin-a" to this package
  [1]
  $ (cd opaque && dune build "$mounted_denied/literal-output")
  File "_build/default/.pkg/mounted-denied/denied/dune", line 11, characters 40-45:
  Error: Program bin-a not found in the tree or in PATH
   (context: default)
  Hint: add a dependency on the package installing "bin-a" to this package
  [1]

