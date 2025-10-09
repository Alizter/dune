Test symlink to directory outside the directory target.

This tests symlinks pointing outside the directory target to other parts of the
build tree. This is likely the reason for the original restriction.

FIXME: This should work once #9873 is fixed.

  $ cat > dune-project << EOF
  > (lang dune 3.21)
  > (using directory-targets 0.1)
  > EOF

Create a directory target to link to:

  $ cat > dune << EOF
  > (rule
  >  (target (dir outside_dir))
  >  (action
  >   (progn
  >    (run mkdir -p outside_dir)
  >    (system "echo 'content' > outside_dir/external.txt"))))
  > 
  > (rule
  >  (target (dir d))
  >  (deps outside_dir)
  >  (action
  >   (progn
  >    (run mkdir -p d)
  >    (chdir d
  >     (run ln -s ../outside_dir link_to_outside)))))
  > EOF

  $ dune build d
  File "dune", lines 8-15, characters 0-144:
   8 | (rule
   9 |  (target (dir d))
  10 |  (deps outside_dir)
  11 |  (action
  12 |   (progn
  13 |    (run mkdir -p d)
  14 |    (chdir d
  15 |     (run ln -s ../outside_dir link_to_outside)))))
  Error: Error trying to read targets after a rule was run:
  - d/link_to_outside: Unexpected file kind "S_DIR" (directory)
  [1]

Test relative symlink to directory outside the target:

  $ cat > dune << EOF
  > (rule
  >  (target (dir outside_dir))
  >  (action
  >   (progn
  >    (run mkdir -p outside_dir)
  >    (system "echo 'content' > outside_dir/external.txt"))))
  > 
  > (rule
  >  (target (dir d2))
  >  (deps outside_dir)
  >  (action
  >   (progn
  >    (run mkdir -p d2)
  >    (chdir d2
  >     (run ln -s ../outside_dir link_to_outside)))))
  > EOF

  $ dune build d2
  File "dune", lines 8-15, characters 0-147:
   8 | (rule
   9 |  (target (dir d2))
  10 |  (deps outside_dir)
  11 |  (action
  12 |   (progn
  13 |    (run mkdir -p d2)
  14 |    (chdir d2
  15 |     (run ln -s ../outside_dir link_to_outside)))))
  Error: Error trying to read targets after a rule was run:
  - d2/link_to_outside: Unexpected file kind "S_DIR" (directory)
  [1]
