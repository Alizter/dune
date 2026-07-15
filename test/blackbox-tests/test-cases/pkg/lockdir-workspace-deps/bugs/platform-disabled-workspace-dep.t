A portable lockdir can contain an inactive branch that depends on a workspace
package enabled only on that branch's platform.

The current test platform is Linux. Declare a workspace package enabled only
on macOS:

  $ export DUNE_CONFIG__PORTABLE_LOCK_DIR=enabled
  $ make_dune_project 3.24
  $ cat >> dune-project <<EOF
  > (using unreleased 0.1)
  > (package
  >  (name ws-macos)
  >  (allow_empty)
  >  (enabled_if (= %{os} macos)))
  > EOF

  $ mkdir dune.lock
  $ cat > dune.lock/lock.dune <<EOF
  > (lang package 0.1)
  > (repositories (complete true))
  > (solved_for_platforms
  >  ((arch x86_64) (os linux))
  >  ((arch x86_64) (os macos)))
  > EOF
  $ make_lockpkg consumer <<'EOF'
  > (version 0.0.1)
  > (depends
  >  (choice
  >   ((((arch x86_64) (os linux))) ())
  >   ((((arch x86_64) (os macos))) (ws-macos))))
  > (build (all_platforms ((action (run echo building-consumer)))))
  > EOF
  $ write_lockdir_consumer_rule

Structural validation checks the inactive macOS edge against only the packages
enabled on Linux and rejects the lockdir:

  $ dune build out
  File "_build/_private/default/.lock/dune.lock/consumer.pkg", line 5,
  characters 33-41:
  The package "consumer" depends on the package "ws-macos", but "ws-macos" does
  not appear in the lockdir _build/_private/default/.lock/dune.lock.
  Error: At least one package dependency is itself not present as a package in
  the lockdir _build/_private/default/.lock/dune.lock.
  Hint: This could indicate that the lockdir is corrupted. Delete it and then
  regenerate it by running: 'dune pkg lock'
  [1]
