Reproduce internal error with dune pkg outdated in #11188.

  $ . ./helpers.sh
  $ mkrepo
  $ mkpkg a
  $ mkpkg b

  $ solve_project<<EOF
  > (lang dune 3.20)
  > (package
  >  (name foo)
  >  (depends a (b :with-dev-setup)))
  > EOF
  Solution for dune.lock:
  - a.0.0.1

Outdated should not run when there's no lock dir in source

  $ dune pkg outdated
  dune.lock does not exist in source, skipping

Copy lock dirs from the build directory to the source

  $ promote_lockdir

dune pkg outdated is able to handle :with-dev-setup correctly.
  $ dune pkg outdated
  dune.lock is up to date.
