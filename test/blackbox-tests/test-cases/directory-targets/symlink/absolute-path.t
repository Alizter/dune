Test symlink to absolute path directory.

This tests what happens with absolute path symlinks pointing both inside and
outside the project. Absolute paths are inherently non-portable and may fail
in sandboxed builds.

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

  $ ls _build/default/d1
  abs_symlink

  $ cat _build/default/d1/abs_symlink/file.txt
  content

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

  $ ls _build/default/d2
  abs_symlink

  $ cat _build/default/d2/abs_symlink/file.txt
  content
