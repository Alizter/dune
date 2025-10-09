Test validation of symlinks that escape the directory target.

Symlinks that point outside the directory target boundary may be problematic
for reproducibility and sandboxing.

  $ cat > dune-project << EOF
  > (lang dune 3.21)
  > (using directory-targets 0.1)
  > EOF

TODO: Determine if this should be forbidden.

Currently, symlinks escaping to sibling directories are allowed:

  $ cat > dune << EOF
  > (rule
  >  (target (dir sibling))
  >  (action
  >   (progn
  >    (run mkdir -p sibling)
  >    (system "echo content > sibling/file.txt"))))
  > 
  > (rule
  >  (target (dir d))
  >  (deps sibling)
  >  (action
  >   (progn
  >    (run mkdir -p d)
  >    (chdir d
  >     (run ln -s ../sibling escape)))))
  > EOF

  $ dune build d

  $ ls _build/default/d
  escape

  $ cat _build/default/d/escape/file.txt
  content

Symlinks escaping to source tree:

  $ mkdir source_dir
  $ touch source_dir/file.txt

First, let's check the actual paths to understand the layout:

  $ cat > dune << EOF
  > (rule
  >  (target (dir d2))
  >  (deps source_dir/file.txt)
  >  (action
  >   (progn
  >    (run mkdir -p d2)
  >    (system "pwd")
  >    (system "touch d2/dummy")
  >    (chdir d2
  >     (system "pwd")))))
  > EOF

  $ dune build d2
  $TESTCASE_ROOT/_build/default
  $TESTCASE_ROOT/_build/default/d2

Now create a symlink to the source tree (3 levels up: d3 -> default -> _build -> root):

  $ cat > dune << EOF
  > (rule
  >  (target (dir d3))
  >  (deps source_dir/file.txt)
  >  (action
  >   (progn
  >    (run mkdir -p d3)
  >    (chdir d3
  >     (run ln -s ../../../source_dir escape_to_source)))))
  > EOF

  $ dune build d3

  $ ls _build/default/d3
  escape_to_source

  $ cat _build/default/d3/escape_to_source/file.txt


