Test symlink to absolute path directory.

This tests what happens with absolute path symlinks pointing both inside and
outside the project. Absolute paths are inherently non-portable and should not
work in sandboxed builds.

FIXME: This should work once #9873 is fixed (though may still fail due to sandbox).

Create a directory outside the dune project:

  $ mkdir -p abs_target_outside
  $ cat > abs_target_outside/file.txt << EOF
  > content
  > EOF

Now create the dune project in a subdirectory:

  $ mkdir project
  $ cd project

  $ cat > dune-project << EOF
  > (lang dune 3.21)
  > (using directory-targets 0.1)
  > EOF

Create a directory inside the project for absolute path testing:

  $ mkdir -p abs_target_inside
  $ cat > abs_target_inside/file.txt << EOF
  > content
  > EOF

Test 1: Absolute symlink to directory inside the project:

  $ cat > dune << EOF
  > (rule
  >  (target (dir d1))
  >  (action
  >   (progn
  >    (run mkdir -p d1)
  >    (run ln -s $PWD/abs_target_inside d1/abs_symlink))))
  > EOF

  $ dune build d1
  File "dune", lines 1-6, characters 0-252:
  1 | (rule
  2 |  (target (dir d1))
  3 |  (action
  4 |   (progn
  5 |    (run mkdir -p d1)
  6 |    (run ln -s $TESTCASE_ROOT/project/abs_target_inside d1/abs_symlink))))
  Error: Error trying to read targets after a rule was run:
  - d1/abs_symlink: Unexpected file kind "S_DIR" (directory)
  [1]

Test 2: Absolute symlink to directory outside the project:

  $ cat > dune << EOF
  > (rule
  >  (target (dir d2))
  >  (action
  >   (progn
  >    (run mkdir -p d2)
  >    (run ln -s $PWD/../abs_target_outside d2/abs_symlink))))
  > EOF

  $ dune build d2
  File "dune", lines 1-6, characters 0-256:
  1 | (rule
  2 |  (target (dir d2))
  3 |  (action
  4 |   (progn
  5 |    (run mkdir -p d2)
  6 |    (run ln -s $TESTCASE_ROOT/project/../abs_target_outside d2/abs_symlink))))
  Error: Error trying to read targets after a rule was run:
  - d2/abs_symlink: Unexpected file kind "S_DIR" (directory)
  [1]
