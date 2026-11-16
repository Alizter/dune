Native locked binaries are narrowed by the requesting package, just like opaque
binaries. A declared dependency is visible to both workspace and mounted
requesters; the same provider is hidden from requesters that do not declare it.

  $ make_lockdir
  $ cat > dune-project <<'EOF'
  > (lang dune 3.25)
  > (package (name allowed) (dir allowed) (depends native-provider))
  > (package (name denied) (dir denied))
  > EOF
  $ mkdir _provider
  $ cat > _provider/dune-project <<'EOF'
  > (lang dune 3.25)
  > (package (name native-provider))
  > EOF
  $ cat > _provider/dune <<'EOF'
  > (install
  >  (section bin)
  >  (files (tool.sh as native-narrowing-tool)))
  > EOF
  $ cat > _provider/tool.sh <<'EOF'
  > #!/bin/sh
  > echo from-native-provider
  > EOF
  $ chmod +x _provider/tool.sh
  $ make_lockpkg native-provider <<EOF
  > (version 1.0)
  > (source (copy $PWD/_provider))
  > (build (run false))
  > EOF

All requesters use the same binary lookups.

  $ cat > rules <<'EOF'
  > (rule
  >  (target available)
  >  (action (write-file %{target} %{bin-available:native-narrowing-tool})))
  > (rule
  >  (target pform-output)
  >  (action (with-stdout-to %{target} (run %{bin:native-narrowing-tool}))))
  > (rule
  >  (target literal-output)
  >  (action (with-stdout-to %{target} (run native-narrowing-tool))))
  > EOF
  $ mkdir allowed denied
  $ cp rules allowed/dune
  $ cp rules denied/dune

A scoped workspace requester can use the declared native provider, without
running its deliberately failing lock recipe.

  $ dune build allowed/available allowed/pform-output allowed/literal-output
  $ cat _build/default/allowed/available
  true
  $ cat _build/default/allowed/pform-output \
  >   _build/default/allowed/literal-output
  from-native-provider
  from-native-provider

The other workspace package cannot discover or run that binary, even after the
provider has been built for the first requester.

  $ dune build denied/available
  $ cat _build/default/denied/available
  false
  $ dune build denied/pform-output
  File "denied/dune", line 6, characters 40-68:
  6 |  (action (with-stdout-to %{target} (run %{bin:native-narrowing-tool}))))
                                              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: Program native-narrowing-tool not found in the tree or in PATH
   (context: default)
  Hint: add a dependency on the package installing "native-narrowing-tool" to
  this package
  [1]
  $ dune build denied/literal-output
  File "denied/dune", line 9, characters 40-61:
  9 |  (action (with-stdout-to %{target} (run native-narrowing-tool))))
                                              ^^^^^^^^^^^^^^^^^^^^^
  Error: Program native-narrowing-tool not found in the tree or in PATH
   (context: default)
  Hint: add a dependency on the package installing "native-narrowing-tool" to
  this package
  [1]

Mounted requesters have the same distinction. Their lock metadata, rather than
the workspace package's dependencies, controls visibility.

  $ mkdir -p _consumers/allowed _consumers/denied
  $ cat > _consumers/dune-project <<'EOF'
  > (lang dune 3.25)
  > (package
  >  (name mounted-allowed)
  >  (dir allowed)
  >  (depends native-provider))
  > (package (name mounted-denied) (dir denied))
  > EOF
  $ cp rules _consumers/allowed/dune
  $ cp rules _consumers/denied/dune
  $ make_lockpkg mounted-allowed <<EOF
  > (version 1.0)
  > (depends native-provider)
  > (source (copy $PWD/_consumers))
  > (build (run false))
  > EOF
  $ make_lockpkg mounted-denied <<EOF
  > (version 1.0)
  > (source (copy $PWD/_consumers))
  > (build (run false))
  > EOF
  $ allowed=_build/default/.pkg/mounted-allowed/allowed
  $ denied=_build/default/.pkg/mounted-denied/denied
  $ dune build "$allowed/available" "$allowed/pform-output" \
  >   "$allowed/literal-output"
  $ cat "$allowed/available"
  true
  $ cat "$allowed/pform-output" "$allowed/literal-output"
  from-native-provider
  from-native-provider
  $ dune build "$denied/available"
  $ cat "$denied/available"
  false
  $ dune build "$denied/pform-output"
  File "_build/default/.pkg/mounted-denied/denied/dune", line 6, characters 40-68:
  Error: Program native-narrowing-tool not found in the tree or in PATH
   (context: default)
  Hint: add a dependency on the package installing "native-narrowing-tool" to
  this package
  [1]
  $ dune build "$denied/literal-output"
  File "_build/default/.pkg/mounted-denied/denied/dune", line 9, characters 40-61:
  Error: Program native-narrowing-tool not found in the tree or in PATH
   (context: default)
  Hint: add a dependency on the package installing "native-narrowing-tool" to
  this package
  [1]
