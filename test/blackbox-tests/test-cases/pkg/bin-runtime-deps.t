A rule using a locked executable must be invalidated when runtime data installed
beside that executable changes.

  $ make_lockdir
  $ make_lockpkg runtime <<'EOF'
  > (version 0.0.1)
  > EOF
  $ make_lockpkg provider <<'EOF'
  > (version 0.0.1)
  > (depends runtime)
  > (install
  >  (progn
  >   (run cp mybin %{pkg-self:bin}/mybin)
  >   (run chmod +x %{pkg-self:bin}/mybin)
  >   (run cp data.txt %{pkg-self:share}/data.txt)))
  > EOF

  $ make_dune_project 3.24
  $ provider_target="$(get_build_pkg_dir provider)/target"
  $ runtime_target="$(get_build_pkg_dir runtime)/target"
  $ provider_data="$PWD/$provider_target/share/provider/data.txt"

  $ make_lockpkg_file provider mybin <<EOF
  > #!/bin/sh
  > cat "$provider_data"
  > EOF
  $ chmod +x dune.lock/provider.files/mybin
  $ echo one >dune.lock/provider.files/data.txt

  $ cat >dune <<'EOF'
  > (rule
  >  (target out)
  >  (action
  >   (with-stdout-to %{target}
  >    (run %{bin:mybin}))))
  > (rule
  >  (target literal-out)
  >  (action
  >   (with-stdout-to %{target} (run mybin))))
  > EOF

Both lookups must depend on the runtime installation and its transitive
dependencies. Check the graph directly: lock digests can change
the executable path and invalidate the rule without these dependencies.

  $ dune build out literal-out
  $ dune rules --format=json out literal-out |
  >   jq_dune -c --arg provider "$provider_target" \
  >     --arg runtime "$runtime_target" '
  >     .[] | { executable: ruleHasDepFile($provider + "/bin/mybin"),
  >             provider: ruleHasDepFile($provider),
  >             runtime: ruleHasDepFile($runtime) }'
  {"executable":true,"provider":true,"runtime":true}
  {"executable":true,"provider":true,"runtime":true}

  $ cat _build/default/out
  one
  $ cp "$provider_target/bin/mybin" mybin.before

Change only runtime data in the package's .files directory.

  $ echo two >dune.lock/provider.files/data.txt
  $ dune build out
  $ cat "$provider_data"
  two
  $ cmp mybin.before "$provider_target/bin/mybin"

The consumer tracks the runtime installation even when the executable
bytes and its digest-qualified path are unchanged.

  $ cat _build/default/out
  two
