Exercises end to end locking and building a simple project.

  $ mkrepo
  $ add_mock_repo_if_needed

Make a library:
  $ make_foo_tarball 'let foo = "Hello, World!"'

Configure our fake curl to serve the tarball

  $ echo foo.tar >> fake-curls
  $ PORT=1

Make a package for the library:
  $ make_foo_tarball_package

Make a project that uses the library:

  $ make_bar_executable_depends_foo_project

Lock, build, and run the executable in the project:

  $ dune_pkg_lock_normalized
  Solution for dune.lock:
  - foo.0.0.1
  $ dune exec bar
  Hello, World!

The standard opam recipe contains dynamic package/job arguments and conditional
`dune subst`, `@runtest`, and `@doc` pieces. Its only unconditional executable
is `dune build`, so source inspection dispatches it to the mounted pipeline:

  $ mounted_root=$(echo _build/_default+lockfile/pkg/foo.0.0.1-*)
  $ test -f "$mounted_root/foo.cmxa" && echo mounted-dune-route
  mounted-dune-route
  $ test ! -e _build/_private/default/.pkg/foo.0.0.1-* && echo no-legacy-package-rules
  no-legacy-package-rules
