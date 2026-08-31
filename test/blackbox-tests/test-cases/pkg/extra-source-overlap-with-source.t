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
  > (build (run cat foo.txt))
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

The extra source overlays the immutable primary source inside the recipe's copy
sandbox:

  $ build_pkg foo
  from extra source
