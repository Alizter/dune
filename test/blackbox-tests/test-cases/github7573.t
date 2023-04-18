Test case for https://github.com/ocaml/dune/issues/7573

This test case demonstrates build failures given the existence of intentially
broken symbollic links, even in data_only_dirs.

  $ cat > dune-project << EOF
  > (lang dune 3.8)
  > EOF

  $ mkdir foo
  $ cat > dune << EOF
  > (data_only_dirs foo)
  > EOF
  $ (cd foo && ln -s doesnt_exist bar)

  $ dune build foo/bar
  File "foo/bar", line 1, characters 0-0:
  Error: Error trying to read targets after a rule was run:
  - foo/bar: Broken symbolic link
  [1]

We also check non-data_only directories with broken links. Dune should complain
about these.

  $ mkdir baz
  $ (cd baz && ln -s doesnt_exist boz)

  $ dune build baz/boz
  File "baz/boz", line 1, characters 0-0:
  Error: Error trying to read targets after a rule was run:
  - baz/boz: Broken symbolic link
  [1]

