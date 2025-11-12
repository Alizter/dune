This test checks what happens when you lock with default directory then change
workspace to use a custom lock directory.

  $ . ./helpers.sh
  $ mkrepo
  $ mkpkg foo
  $ add_mock_repo_if_needed

  $ cat > dune-project <<EOF
  > (lang dune 3.21)
  > (package
  >  (name myproject)
  >  (depends foo))
  > EOF

Lock with default directory name:

  $ dune pkg lock
  Solution for dune.lock:
  - foo.0.0.1

Now change the workspace to use a custom lock directory:

  $ cat > dune-workspace <<EOF
  > (lang dune 3.21)
  > (lock_dir
  >  (path custom.lock)
  >  (repositories mock))
  > (repository
  >  (name mock)
  >  (url "file://$PWD/mock-opam-repository"))
  > EOF

  $ dune build
  Error: The package myproject does not have any user defined stanzas attached
  to it. If this is intentional, add (allow_empty) to the package definition in
  the dune-project file
  -> required by _build/default/myproject.install
  -> required by alias all
  -> required by alias default
  [1]

Now try with a context stanza that references the custom lock directory with a
context stanza:

  $ cat > dune-workspace <<EOF
  > (lang dune 3.21)
  > (context
  >  (default
  >   (lock_dir custom.lock)))
  > (lock_dir
  >  (path custom.lock)
  >  (repositories mock))
  > (repository
  >  (name mock)
  >  (url "file://$PWD/mock-opam-repository"))
  > EOF

This is working as intended. The error is not relevant here.

  $ dune build
  Error: The package myproject does not have any user defined stanzas attached
  to it. If this is intentional, add (allow_empty) to the package definition in
  the dune-project file
  -> required by _build/default/myproject.install
  -> required by alias all
  -> required by alias default
  [1]
