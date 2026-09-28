Test for packages with an extra-source file with the same name as a
file in the package's source.

  $ make_lockdir
  $ make_lockpkg foo <<EOF
  > (version 1)
  > (build (run cp foo.txt observed))
  > (source
  >  (copy $PWD/foo-source))
  > (extra_sources
  >  (foo.txt
  >   (fetch
  >    (url file://$PWD/foo.txt))))
  > EOF

  $ mkdir -p foo-source
  $ echo "from source" > foo-source/foo.txt
  $ echo 'share: [ "observed" ]' > foo-source/foo.install

  $ echo "from extra source" > foo.txt

  $ cat > dune-project <<EOF
  > (lang dune 3.16)
  > (package
  >  (allow_empty)
  >  (name a)
  >  (depends foo))
  > EOF

  $ build_pkg foo

The build action observes the overlay before installation, without modifying
the workspace input:

  $ cat "$(get_build_pkg_dir foo)/target/share/foo/observed"
  from extra source
  $ cat foo-source/foo.txt
  from source

The prepared source directory also stays unchanged. The overlay is confined to
the writable build copy:

  $ cat _build/_fetch/url/*/dir/foo.txt
  from source
