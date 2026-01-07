Test if version_preference applies to selected depopts.

  $ mkrepo

  $ mkpkg foo 1.0.0
  $ mkpkg foo 2.0.0
  $ mkpkg foo 3.0.0

  $ cat >dune-project <<EOF
  > (lang dune 3.18)
  > (package
  >  (name x)
  >  (depopts foo))
  > EOF

Without version_preference, depopts get newest:

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

With version_preference oldest, depopts should get oldest:

  $ cat >dune-workspace <<EOF
  > (lang dune 3.18)
  > (lock_dir
  >  (depopts foo)
  >  (version_preference oldest)
  >  (repositories mock))
  > (repository
  >  (name mock)
  >  (url "file://$PWD/mock-opam-repository"))
  > EOF

  $ dune_pkg_lock_normalized
  Solution for dune.lock:
  - foo.1.0.0
