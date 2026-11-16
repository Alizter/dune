Solver preferences and system-package hints do not change a package's build.
Currently they change its key, but the action is not rerun.

  $ export DUNE_TRACE=+cache
  $ misses() {
  >   dune trace cat | jq -cs '
  >     [ .[]
  >       | select(.cat == "cache" and .name == "workspace_local_miss")
  >       | select(.args.target | endswith("/foo/_install"))
  >       | .args.reason | split(":")[0]
  >     ]
  >   '
  > }
  $ make_dune_project 3.26
  $ make_lockdir
  $ make_lockpkg foo <<EOF
  > (version 1)
  > (build (system "true"))
  > EOF
  $ cp dune.lock/foo.pkg original.pkg
  $ build_pkg foo
  $ build_pkg foo
  $ misses
  []

Changing only the solver's avoid preference currently changes the key.

  $ printf '\n(avoid)\n' >> dune.lock/foo.pkg
  $ build_pkg foo
  $ misses
  []

Changing only a system-package hint also changes it.

  $ cp original.pkg dune.lock/foo.pkg
  $ printf '\n(depexts system-package-hint)\n' >> dune.lock/foo.pkg
  $ build_pkg foo
  $ misses
  []
