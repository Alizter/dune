Test interaction between depopts and pins in the lock_dir stanza.

  $ mkrepo
  $ add_mock_repo_if_needed

Create a pinned package:

  $ mkdir _foo
  $ cat >_foo/dune-project <<EOF
  > (lang dune 3.18)
  > (package (name foo))
  > EOF

  $ cat >dune-project <<EOF
  > (lang dune 3.18)
  > (package
  >  (name x)
  >  (depopts foo))
  > EOF

Select foo as depopt and pin it:

  $ cat >dune-workspace <<EOF
  > (lang dune 3.18)
  > (pin
  >  (name foo)
  >  (url "file://$PWD/_foo")
  >  (package (name foo)))
  > (lock_dir
  >  (depopts foo)
  >  (pins foo)
  >  (repositories mock))
  > (repository
  >  (name mock)
  >  (url "file://$PWD/mock-opam-repository"))
  > EOF

  $ dune_pkg_lock_normalized
  Solution for dune.lock:
  - foo.dev
