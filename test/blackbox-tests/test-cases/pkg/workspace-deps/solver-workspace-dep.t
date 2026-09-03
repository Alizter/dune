[dune pkg lock] is asked to lock a project where a mock-repository
package depends on a workspace package.

  $ mkrepo
  $ add_mock_repo_if_needed

The mock package [mylock] declares the workspace package [util] as a
dependency:

  $ mkpkg mylock <<EOF
  > depends: [
  >  "util"
  > ]
  > EOF

The workspace has two packages: [main] depends on the mock package
[mylock], and [util] has no dependencies.

  $ make_dune_project 3.24
  $ cat >> dune-project <<EOF
  > (package (name main) (allow_empty) (depends mylock))
  > (package (name util) (allow_empty))
  > EOF

The solver records [util] as a dependency of [mylock] without adding the
workspace package itself to the lockdir:

  $ dune pkg lock
  Solution for dune.lock
  
  Dependencies common to all supported platforms:
  - mylock.0.0.1

  $ ls dune.lock/*.pkg
  dune.lock/mylock.0.0.1.pkg

  $ cat dune.lock/mylock.0.0.1.pkg
  (version 0.0.1)
  
  (depends
   (all_platforms (util)))

The generated lockdir can be interpreted by the normal package rules:

  $ cat > dune <<'EOF'
  > (rule
  >  (deps (package mylock))
  >  (action (with-stdout-to out (echo ok))))
  > EOF
  $ dune build out

  $ find _build/install/default/.packages -type f -o -type l | censor | sort
  _build/install/default/.packages/$DIGEST/lib/util/META
  _build/install/default/.packages/$DIGEST/lib/util/dune-package

Relocking the same workspace also succeeds:

  $ dune pkg lock
  Solution for dune.lock
  
  Dependencies common to all supported platforms:
  - mylock.0.0.1
