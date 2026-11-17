Package dependencies and executable dependencies can overlap in a sandbox.
Cross native/opaque providers with/without [(deps (package provider))],
default/copy sandboxing, and literal/pform program lookup. The project package
always depends on the provider; all cells share their source definitions.

  $ export DUNE_CACHE=disabled
  $ mkdir _provider _consumer native opaque
  $ (cd _provider && make_dune_project_with_package 3.25 provider)
  $ echo '(install (section bin) (files mybin))' > _provider/dune
  $ cat > _provider/mybin <<'EOF'
  > #!/bin/sh
  > printf 'from provider: %s\n' "$1"
  > EOF
  $ chmod +x _provider/mybin
  $ cat > _consumer/dune-project <<'EOF'
  > (lang dune 3.25)
  > (package (name main) (dir .) (allow_empty) (depends provider))
  > EOF
  $ cat > _consumer/dune <<'EOF'
  > (alias
  >  (name check)
  >  (deps with-dep-literal with-dep-pform
  >        without-dep-literal without-dep-pform))
  > (rule
  >  (target with-dep-literal)
  >  (deps (package provider) (sandbox always))
  >  (action (with-stdout-to %{target} (run mybin literal))))
  > (rule
  >  (target with-dep-pform)
  >  (deps (package provider) (sandbox always))
  >  (action (with-stdout-to %{target} (run %{bin:mybin} pform))))
  > (rule
  >  (target without-dep-literal)
  >  (deps (sandbox always))
  >  (action (with-stdout-to %{target} (run mybin literal))))
  > (rule
  >  (target without-dep-pform)
  >  (deps (sandbox always))
  >  (action (with-stdout-to %{target} (run %{bin:mybin} pform))))
  > EOF

Both user rules require sandboxing. Prefer none for internal rules, then copy
for the user rules; this makes copy mode effective even without a package dep.

  $ cat > _consumer/copy-config <<'EOF'
  > (lang dune 3.25)
  > (sandboxing_preference none copy)
  > EOF
  $ cp _consumer/* native/
  $ cp _consumer/* opaque/
  $ (cd native && make_lockdir &&
  >  make_dune_source_lockpkg native provider "$PWD/../_provider")
  $ (cd opaque && make_lockdir &&
  >  make_dune_source_lockpkg opaque provider "$PWD/../_provider")

Native provider, default sandboxing, with and without a package dependency.
Literal and pform lookups have separate actions, so neither supplies the
other's sandbox dependencies.

  $ (cd native && dune build @check)
  $ cat native/_build/default/*-dep-*
  from provider: literal
  from provider: pform
  from provider: literal
  from provider: pform

Native provider, copy sandboxing. Remove the outputs to rerun every action.

  $ rm native/_build/default/*-dep-*
  $ (cd native && dune build @check --config-file copy-config)
  $ cat native/_build/default/*-dep-*
  from provider: literal
  from provider: pform
  from provider: literal
  from provider: pform
  $ test ! -e native/_build/default/.pkg/provider/_install/cookie
  $ test ! -e native/_build/default/.pkg/provider/_install/opaque-recipe

Opaque provider, default sandboxing, with the same consumers and lookups.

  $ (cd opaque && dune build @check)
  $ cat opaque/_build/default/*-dep-*
  from provider: literal
  from provider: pform
  from provider: literal
  from provider: pform

Opaque provider, copy sandboxing. The package directory and the executable
inside it must not be copied twice when both dependencies are present.

  $ rm opaque/_build/default/*-dep-*
  $ (cd opaque && dune build @check --config-file copy-config)
  $ cat opaque/_build/default/*-dep-*
  from provider: literal
  from provider: pform
  from provider: literal
  from provider: pform
  $ cat opaque/_build/default/.pkg/provider/_install/opaque-recipe
  opaque
  $ test -f opaque/_build/default/.pkg/provider/_install/cookie
  $ test ! -e _provider/opaque-recipe
