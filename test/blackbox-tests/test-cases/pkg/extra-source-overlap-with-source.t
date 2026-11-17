Test for packages with an extra-source file with the same name as a
file in the package's source.

  $ make_lockdir
  $ make_lockpkg foo <<EOF
  > (version 1)
  > (source
  >  (copy $PWD/foo-source))
  > (extra_sources
  >  (foo.txt
  >   (fetch
  >    (url file://$PWD/foo.txt))))
  > EOF

  $ mkdir -p foo-source
  $ echo "from source" > foo-source/foo.txt

  $ echo "from extra source" > foo.txt

  $ cat > dune-project <<EOF
  > (lang dune 3.16)
  > (package
  >  (allow_empty)
  >  (name a)
  >  (depends foo))
  > EOF

  $ build_pkg foo

Even without build or install actions, overlays must not modify either input.

  $ cat foo-source/foo.txt foo.txt
  from source
  from extra source

If foo.txt exists in both the main source and extra_sources, a build action
must read the extra_sources version. Both original inputs must retain their
contents.

  $ make_lockpkg foo <<EOF
  > (version 1)
  > (build (run cp foo.txt observed))
  > (source (copy $PWD/foo-source))
  > (extra_sources
  >  (foo.txt (fetch (url file://$PWD/foo.txt))))
  > EOF
  $ echo 'share: [ "observed" ]' > foo-source/foo.install
  $ build_pkg foo
  $ cat "$(get_build_pkg_dir foo)/_install/share/foo/observed"
  from extra source
  $ cat foo-source/foo.txt
  from source

The mount contains the overlay, while the original source remains unchanged:

  $ cat _build/default/.pkg/foo/foo.txt
  from extra source
