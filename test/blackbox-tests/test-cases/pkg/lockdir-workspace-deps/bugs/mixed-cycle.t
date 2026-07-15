Validation and rule construction must reject the same dependency cycles. This
case forms a cycle across the workspace/lockdir boundary:

w (workspace) -> a (lockdir) -> w (workspace)

First generate a valid lockdir and dependency hash for the workspace edge to
a:

  $ mkrepo
  $ mkpkg a
  $ add_mock_repo_if_needed
  $ solve_project <<EOF
  > (lang dune 3.24)
  > (package
  >  (name w)
  >  (allow_empty)
  >  (depends a))
  > EOF
  Solution for dune.lock:
  - a.0.0.1

Complete the mixed cycle by making locked package a depend on workspace
package w:

  $ cat > dune.lock/a.0.0.1.pkg <<EOF
  > (version 0.0.1)
  > (depends (all_platforms (w)))
  > EOF

The command-path validator currently rejects the workspace dependency before
it can report the cycle:

  $ dune pkg validate-lockdir
  File "dune.lock/a.0.0.1.pkg", line 2, characters 25-26:
  The package "a" depends on the package "w", but "w" does not appear in the
  lockdir dune.lock.
  Failed to parse lockdir dune.lock:
  Error: At least one package dependency is itself not present as a package in
  the lockdir dune.lock.
  Hint: This could indicate that the lockdir is corrupted. Delete it and then
  regenerate it by running: 'dune pkg lock'
  
  Error: Some lockdirs do not contain solutions for local packages:
  - dune.lock
  [1]

The build path accepts the same cycle:

  $ cat > dune <<'EOF'
  > (rule
  >  (deps (package a))
  >  (action (with-stdout-to out (echo ok))))
  > EOF
  $ dune build out && echo accepted
  accepted
