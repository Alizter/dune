Package commands reject a workspace-dependent lockdir that the build path
accepts.

  $ mkrepo
  $ mkpkg consumer
  $ add_mock_repo_if_needed
  $ solve_project <<EOF
  > (lang dune 3.24)
  > (package
  >  (name workspace-lib)
  >  (allow_empty))
  > (package
  >  (name app)
  >  (allow_empty)
  >  (depends consumer))
  > EOF
  Solution for dune.lock:
  - consumer.0.0.1

Add the workspace dependency without changing the package selected for the
local app:

  $ cat > dune.lock/consumer.0.0.1.pkg <<EOF
  > (version 0.0.1)
  > (depends (all_platforms (workspace-lib)))
  > EOF
  $ cat > dune <<'EOF'
  > (rule
  >  (deps (package consumer))
  >  (action (with-stdout-to out (echo ok))))
  > EOF

The build path recognizes workspace-lib:

  $ dune build out

The standalone lockdir readers do not:

  $ dune pkg validate-lockdir
  File "dune.lock/consumer.0.0.1.pkg", line 2, characters 25-38:
  The package "consumer" depends on the package "workspace-lib", but
  "workspace-lib" does not appear in the lockdir dune.lock.
  Failed to parse lockdir dune.lock:
  Error: At least one package dependency is itself not present as a package in
  the lockdir dune.lock.
  Hint: This could indicate that the lockdir is corrupted. Delete it and then
  regenerate it by running: 'dune pkg lock'
  
  Error: Some lockdirs do not contain solutions for local packages:
  - dune.lock
  [1]
  $ dune describe pkg lock
  File "dune.lock/consumer.0.0.1.pkg", line 2, characters 25-38:
  The package "consumer" depends on the package "workspace-lib", but
  "workspace-lib" does not appear in the lockdir dune.lock.
  Error: At least one package dependency is itself not present as a package in
  the lockdir dune.lock.
  Hint: This could indicate that the lockdir is corrupted. Delete it and then
  regenerate it by running: 'dune pkg lock'
  [1]
  $ dune describe pkg list-locked-dependencies
  File "dune.lock/consumer.0.0.1.pkg", line 2, characters 25-38:
  The package "consumer" depends on the package "workspace-lib", but
  "workspace-lib" does not appear in the lockdir dune.lock.
  Warning: Failed to parse lockdir dune.lock:
  Error: At least one package dependency is itself not present as a package in
  the lockdir dune.lock.
  Hint: This could indicate that the lockdir is corrupted. Delete it and then
  regenerate it by running: 'dune pkg lock'
  
  
  $ dune pkg outdated
  File "dune.lock/consumer.0.0.1.pkg", line 2, characters 25-38:
  The package "consumer" depends on the package "workspace-lib", but
  "workspace-lib" does not appear in the lockdir dune.lock.
  Error: At least one package dependency is itself not present as a package in
  the lockdir dune.lock.
  Hint: This could indicate that the lockdir is corrupted. Delete it and then
  regenerate it by running: 'dune pkg lock'
  [1]
