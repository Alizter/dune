A --rev build should not scan the working tree at all — only the
rev's tree. We exercise this by putting a file in the working tree
that would cause dune to error if scanned (a duplicate dune-project
in a subdir), and a clean snapshot in the rev.

  $ git init --quiet

Initial commit: a clean project that builds successfully.

  $ make_dune_project 3.25
  $ cat > dune << EOF
  > (rule
  >  (target greeting)
  >  (action (with-stdout-to %{target} (echo "hello"))))
  > EOF
  $ git add .
  $ git commit -q -m "initial"

Working tree gets a broken dune file in a subdirectory that would
make a plain dune build fail.

  $ mkdir sub
  $ cat > sub/dune << EOF
  > (this is not valid dune syntax)
  > EOF

A plain build fails because dune walks into [sub/] and chokes.

  $ dune build greeting 2>&1
  File "sub/dune", line 1, characters 1-5:
  1 | (this is not valid dune syntax)
       ^^^^
  Error: Unknown constructor this
  [1]

A --rev build at the committed revision should succeed because
[sub/] doesn't exist there — and crucially, dune should not be
scanning the working tree at all.

  $ dune build --rev HEAD greeting
  $ short=$(git rev-parse HEAD | cut -c1-12)
  $ cat "_build/default-$short/greeting"
  hello
