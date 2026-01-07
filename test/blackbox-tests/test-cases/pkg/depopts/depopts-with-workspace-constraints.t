Demonstrate how depopts and constraints interact in the workspace lock_dir stanza.

BUG: Constraints are NOT applied to selected depopts. This test documents the
current (broken) behavior where constraints are ignored.

  $ mkrepo

Create multiple versions of a package that will be used as a depopt

  $ mkpkg foo 1.0.0
  $ mkpkg foo 2.0.0
  $ mkpkg foo 3.0.0

Create a local package that has foo as an optional dependency

  $ solve_project <<EOF
  > (lang dune 3.18)
  > (package
  >  (name x)
  >  (depopts foo))
  > EOF
  Solution for dune.lock:
  (no dependencies to lock)

Without any workspace configuration, foo is not selected (it's optional)

Select foo as a depopt without constraints - gets latest version

  $ cat >dune-workspace <<EOF
  > (lang dune 3.18)
  > (lock_dir
  >  (depopts foo)
  >  (repositories mock))
  > (repository
  >  (name mock)
  >  (url "file://$PWD/mock-opam-repository"))
  > EOF

  $ dune_pkg_lock_normalized
  Solution for dune.lock:
  - foo.3.0.0

BUG: Constraint in workspace is ignored - still gets latest version

  $ cat >dune-workspace <<EOF
  > (lang dune 3.18)
  > (lock_dir
  >  (depopts foo)
  >  (constraints (foo (= 1.0.0)))
  >  (repositories mock))
  > (repository
  >  (name mock)
  >  (url "file://$PWD/mock-opam-repository"))
  > EOF

  $ dune_pkg_lock_normalized
  Solution for dune.lock:
  - foo.3.0.0

BUG: Range constraint in workspace is also ignored

  $ cat >dune-workspace <<EOF
  > (lang dune 3.18)
  > (lock_dir
  >  (depopts foo)
  >  (constraints (foo (< 3.0.0)))
  >  (repositories mock))
  > (repository
  >  (name mock)
  >  (url "file://$PWD/mock-opam-repository"))
  > EOF

  $ dune_pkg_lock_normalized
  Solution for dune.lock:
  - foo.3.0.0

Constraint without depopt - foo is NOT included (constraints don't add packages)

  $ cat >dune-workspace <<EOF
  > (lang dune 3.18)
  > (lock_dir
  >  (constraints (foo (= 1.0.0)))
  >  (repositories mock))
  > (repository
  >  (name mock)
  >  (url "file://$PWD/mock-opam-repository"))
  > EOF

  $ dune_pkg_lock_normalized
  Solution for dune.lock:
  (no dependencies to lock)

BUG: Constraint directly in dune-project's depopts field is also ignored

  $ cat >dune-project <<EOF
  > (lang dune 3.18)
  > (package
  >  (name x)
  >  (depopts (foo (= 1.0.0))))
  > EOF

  $ cat >dune-workspace <<EOF
  > (lang dune 3.18)
  > (lock_dir
  >  (depopts foo)
  >  (repositories mock))
  > (repository
  >  (name mock)
  >  (url "file://$PWD/mock-opam-repository"))
  > EOF

  $ dune_pkg_lock_normalized
  Solution for dune.lock:
  - foo.3.0.0
