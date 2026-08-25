HTTP archives are fetched before source inspection. A Dune project with a pure
Dune build action is then mounted and built in the workspace rule graph.

  $ mkrepo
  $ add_mock_repo_if_needed

Make a Dune library archive and configure the fake HTTP transport:

  $ make_foo_tarball 'let foo = "Hello over HTTP"'
  $ echo foo.tar >> fake-curls
  $ PORT=1

The package action is deliberately only a Dune build, making the source eligible
for the mounted route after the archive has been inspected:

  $ mkpkg foo <<EOF
  > build: [["dune" "build" "@install"]]
  > url {
  >   src: "http://0.0.0.0:${PORT}"
  >   checksum: [
  >     "md5=$(md5sum foo.tar | cut -f1 -d' ')"
  >   ]
  > }
  > EOF

  $ make_bar_executable_depends_foo_project
  $ dune_pkg_lock_normalized
  Solution for dune.lock:
  - foo.0.0.1
  $ dune exec bar
  Hello over HTTP

  $ mounted_root=$(echo _build/_default+lockfile/pkg/foo.0.0.1-*)
  $ test -f "$mounted_root/foo.cmxa" && echo mounted-http-package
  mounted-http-package
  $ test ! -d _build/_private/default/.pkg/foo.0.0.1-* && echo no-old-package-rules
  no-old-package-rules
