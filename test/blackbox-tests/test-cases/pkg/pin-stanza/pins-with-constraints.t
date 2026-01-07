Test interaction between pins and constraints in the lock_dir stanza.

  $ mkrepo

Create a pinned package:

  $ mkdir _foo
  $ cat >_foo/dune-project <<EOF
  > (lang dune 3.18)
  > (package (name foo))
  > EOF

  $ cat >dune-project <<EOF
  > (lang dune 3.18)
  > (package
  >  (name main)
  >  (depends foo))
  > EOF

Pin foo and use it:

  $ cat >dune-workspace <<EOF
  > (lang dune 3.18)
  > (pin
  >  (name foo)
  >  (url "file://$PWD/_foo")
  >  (package (name foo)))
  > (lock_dir
  >  (pins foo)
  >  (repositories mock))
  > (repository
  >  (name mock)
  >  (url "file://$PWD/mock-opam-repository"))
  > EOF

  $ dune_pkg_lock_normalized
  Solution for dune.lock:
  - foo.dev

Constraints are applied to pinned packages. A conflicting constraint fails:

  $ cat >dune-workspace <<EOF
  > (lang dune 3.18)
  > (pin
  >  (name foo)
  >  (url "file://$PWD/_foo")
  >  (package (name foo)))
  > (lock_dir
  >  (pins foo)
  >  (constraints (foo (= 2.0.0)))
  >  (repositories mock))
  > (repository
  >  (name mock)
  >  (url "file://$PWD/mock-opam-repository"))
  > EOF

  $ dune_pkg_lock_normalized
  Error:
  Unable to solve dependencies while generating lock directory: dune.lock
  
  Couldn't solve the package dependency formula.
  Selected candidates: main.dev
  - foo -> (problem)
      main dev requires = 2.0.0
      Rejected candidates:
        foo.dev: Incompatible with restriction: = 2.0.0
  [1]


A matching constraint works:

  $ cat >dune-workspace <<EOF
  > (lang dune 3.18)
  > (pin
  >  (name foo)
  >  (url "file://$PWD/_foo")
  >  (package (name foo)))
  > (lock_dir
  >  (pins foo)
  >  (constraints (foo (>= 0.0.0)))
  >  (repositories mock))
  > (repository
  >  (name mock)
  >  (url "file://$PWD/mock-opam-repository"))
  > EOF

  $ dune_pkg_lock_normalized
  Solution for dune.lock:
  - foo.dev
