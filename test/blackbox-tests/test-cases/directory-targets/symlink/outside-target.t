Test symlink to directory outside the directory target.

This tests symlinks pointing outside the directory target to other parts of the
build tree.

TODO: Validate whether symlinks escaping the directory target boundary should
be forbidden for reproducibility/sandboxing concerns.

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

  $ ls _build/default/d
  link_to_outside

  $ cat _build/default/d/link_to_outside/external.txt
  content

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

  $ cat _build/default/d2/link_to_outside/external.txt
  content
