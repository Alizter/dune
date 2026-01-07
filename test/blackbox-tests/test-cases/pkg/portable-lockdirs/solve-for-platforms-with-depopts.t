Test interaction between solve_for_platforms and depopts.

  $ mkrepo

  $ mkpkg foo

  $ cat >dune-project <<EOF
  > (lang dune 3.18)
  > (package
  >  (name x)
  >  (depopts foo))
  > EOF

Select depopt with solve_for_platforms:

  $ cat >dune-workspace <<EOF
  > (lang dune 3.20)
  > (repository
  >  (name mock)
  >  (url "file://$PWD/mock-opam-repository"))
  > (lock_dir
  >  (depopts foo)
  >  (repositories mock)
  >  (solve_for_platforms
  >   ((arch x86_64)
  >    (os linux))))
  > EOF

  $ dune pkg lock
  Solution for dune.lock
  
  Dependencies common to all supported platforms:
  - foo.0.0.1

