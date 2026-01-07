Constraints with platform filters do not work as expected.

  $ mkrepo

  $ mkpkg foo 1.0.0
  $ mkpkg foo 2.0.0
  $ mkpkg foo 3.0.0

  $ cat >dune-project <<EOF
  > (lang dune 3.22)
  > (package
  >  (name x)
  >  (depends foo))
  > EOF

Constraint with platform filter - does NOT apply (BUG: foo is not in solution):

  $ cat >dune-workspace <<EOF
  > (lang dune 3.22)
  > (lock_dir
  >  (solver_env (os linux))
  >  (constraints (foo (and (= :os linux) (< 2.0.0))))
  >  (repositories mock))
  > (repository
  >  (name mock)
  >  (url "file://$PWD/mock-opam-repository"))
  > EOF

  $ dune pkg lock 2>&1 | head -5
  Solution for dune.lock
  
  Dependencies common to all supported platforms:
  (none)
  



Constraint without platform filter works correctly:

  $ cat >dune-workspace <<EOF
  > (lang dune 3.22)
  > (lock_dir
  >  (constraints (foo (< 2.0.0)))
  >  (repositories mock))
  > (repository
  >  (name mock)
  >  (url "file://$PWD/mock-opam-repository"))
  > EOF

  $ dune pkg lock 2>&1 | head -5
  Solution for dune.lock
  
  Dependencies common to all supported platforms:
  - foo.1.0.0

