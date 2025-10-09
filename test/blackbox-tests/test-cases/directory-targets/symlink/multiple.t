Test multiple symlinks to directories.

Multiple directory symlinks in the same directory target, including a symlink to
another symlink.

FIXME: This should work once #9873 is fixed.

  $ cat > dune-project << EOF
  > (lang dune 3.21)
  > (using directory-targets 0.1)
  > EOF

  $ cat > dune << EOF
  > (rule
  >  (target (dir d))
  >  (action
  >   (progn
  >    (run mkdir -p d)
  >    (chdir d
  >     (progn
  >      (run mkdir real_dir1)
  >      (run mkdir real_dir2)
  >      (run ln -s real_dir1 link1)
  >      (run ln -s real_dir2 link2)
  >      (run ln -s link1 link_to_link))))))
  > EOF

  $ dune build d
  File "dune", lines 1-12, characters 0-245:
   1 | (rule
   2 |  (target (dir d))
   3 |  (action
  ....
  10 |      (run ln -s real_dir1 link1)
  11 |      (run ln -s real_dir2 link2)
  12 |      (run ln -s link1 link_to_link))))))
  Error: Error trying to read targets after a rule was run:
  - d/link1: Unexpected file kind "S_DIR" (directory)
  - d/link2: Unexpected file kind "S_DIR" (directory)
  - d/link_to_link: Unexpected file kind "S_DIR" (directory)
  [1]
