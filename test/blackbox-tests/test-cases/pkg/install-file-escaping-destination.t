An install file entry may name a destination outside its section's directory
for the package, as opam allows. A dependent finds the file where it was
installed.

  $ make_lockdir
  $ make_lockpkg escape <<'EOF2'
  > (version 1.0)
  > (build
  >  (progn
  >   (write-file META meta)
  >   (write-file escape.install "lib: [ \"META\" {\"../other/META\"} ]")))
  > EOF2
  $ make_lockpkg consumer <<'EOF2'
  > (version 1.0)
  > (depends escape)
  > (build (run echo built))
  > EOF2
  $ build_pkg consumer
  built
  $ find _build/_private/default/.packages -name META | sed -E 's#packages/[^/]+#packages/$DIGEST#'
  _build/_private/default/.packages/$DIGEST/lib/other/META
