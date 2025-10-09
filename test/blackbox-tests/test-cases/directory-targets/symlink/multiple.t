Test multiple symlinks to directories.

Multiple directory symlinks in the same directory target, including a symlink to
another symlink.

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

  $ ls _build/default/d
  link1
  link2
  link_to_link
  real_dir1
  real_dir2
