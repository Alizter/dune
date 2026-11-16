Test fetching from git

  $ mkdir somerepo
  $ cd somerepo
  $ git init --quiet
  $ echo "hello world" > foo
  $ git add foo
  $ git commit -am _ --quiet
  $ cd ..

  $ MYGITREPO=$PWD/somerepo

  $ mkdir foo && cd foo
  $ make_lockdir
  $ make_lockpkg test <<EOF
  > (version 0.0.1)
  > (source (fetch (url "git+file://$MYGITREPO")))
  > (build (run cat foo))
  > EOF

Loading fetch rules must not resolve Git sources of unrelated packages.
Currently the unused package's repository is contacted (see S7 in PLAN.md);
the build itself still succeeds.

  $ make_lockpkg unused <<EOF
  > (version 0.0.1)
  > (source (fetch (url "git+file://$PWD/missing-repo")))
  > EOF

  $ build_pkg test
  fatal: '$TESTCASE_ROOT/foo/missing-repo' does not appear to be a git repository
  fatal: Could not read from remote repository.
  
  Please make sure you have the correct access rights
  and the repository exists.
  hello world
