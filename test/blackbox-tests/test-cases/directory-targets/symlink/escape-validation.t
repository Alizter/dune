Test validation of symlinks that escape the directory target.

Symlinks that point outside the directory target boundary are forbidden
for reproducibility and sandboxing concerns.

  $ cat > dune-project << EOF
  > (lang dune 3.21)
  > (using directory-targets 0.1)
  > EOF

Symlinks escaping to sibling directories are now forbidden:

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
  File "dune", lines 8-15, characters 0-127:
   8 | (rule
   9 |  (target (dir d))
  10 |  (deps sibling)
  11 |  (action
  12 |   (progn
  13 |    (run mkdir -p d)
  14 |    (chdir d
  15 |     (run ln -s ../sibling escape)))))
  Error: Symbolic link "d/escape" escapes the directory target
  [1]

Symlinks escaping to source tree are also forbidden:

  $ mkdir source_dir
  $ touch source_dir/file.txt

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
  File "dune", lines 1-8, characters 0-161:
  1 | (rule
  2 |  (target (dir d3))
  3 |  (deps source_dir/file.txt)
  4 |  (action
  5 |   (progn
  6 |    (run mkdir -p d3)
  7 |    (chdir d3
  8 |     (run ln -s ../../../source_dir escape_to_source)))))
  Error: Symbolic link "d3/escape_to_source" escapes the directory target
  [1]


