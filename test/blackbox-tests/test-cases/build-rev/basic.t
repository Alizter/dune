  $ git init --quiet

Set up a small project that emits a known string and commit it.

  $ make_dune_project 3.25
  $ cat > dune << EOF
  > (rule
  >  (target greeting)
  >  (deps src.txt)
  >  (action (with-stdout-to %{target} (bash "cat src.txt"))))
  > EOF
  $ echo "hello from HEAD" > src.txt
  $ git add .
  $ git commit -q -m "initial"

Now edit the source to change the output in the working tree.

  $ echo "hello from working tree" > src.txt

A plain build sees the working tree.

  $ dune build greeting
  $ cat _build/default/greeting
  hello from working tree

A build at the committed revision sees the committed source instead,
into a separate per-rev build dir.

  $ dune build --rev HEAD greeting
  $ short=$(git rev-parse HEAD | cut -c1-12)
  $ cat "_build/default-$short/greeting"
  hello from HEAD

The plain build dir is untouched by the --rev build.

  $ cat _build/default/greeting
  hello from working tree
