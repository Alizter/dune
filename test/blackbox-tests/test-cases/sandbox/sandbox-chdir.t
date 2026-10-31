If an action [chdir]s to a non-existing directory, it is created.

  $ echo '(lang dune 2.6)' > dune-project
  $ cat > dune <<EOF
  > (rule
  >  (targets t)
  >  (deps (sandbox none))
  >  (action
  >  (chdir dir
  >   (progn
  >    (no-infer (write-file file hi))
  >    (write-file ../t hi)))))
  > EOF
  $ dune build t
  $ cat _build/default/dir/file
  hi
  $ cat _build/default/t
  hi

Now the same but with sandboxing. The action succeeds but the directory is not
re-created in the build directory.

  $ cat > dune <<EOF
  > (rule
  >  (targets t)
  >  (deps (sandbox always))
  >  (action
  >   (chdir dir
  >    (progn
  >     (run true)
  >     (no-infer (write-file file hi))
  >     (write-file ../t hi)))))
  > EOF
  $ dune build t
  $ cat _build/default/dir/file
  cat: _build/default/dir/file: No such file or directory
  [1]
  $ cat _build/default/t
  hi

Show errors when [chdir]ing outside of the build directory.

  $ cat > dune <<EOF
  > (rule
  >  (targets t)
  >  (deps (sandbox none))
  >  (action
  >   (chdir /dir
  >    (progn
  >     (no-infer (write-file file hi))
  >     (write-file ../t hi)))))
  > EOF
  $ dune build t
  File "dune", line 5, characters 9-13:
  5 |   (chdir /dir
               ^^^^
  Error: Directory /dir is outside the build directory. This is not allowed.
  [1]

  $ cat > dune <<EOF
  > (rule
  >  (targets t)
  >  (deps (sandbox none))
  >  (action (chdir ../../dir (progn (no-infer (write-file file hi)) (write-file ../t hi)))))
  > EOF
  $ dune build t
  File "dune", line 4, characters 16-25:
  4 |  (action (chdir ../../dir (progn (no-infer (write-file file hi)) (write-file ../t hi)))))
                      ^^^^^^^^^
  Error: Directory
  $TESTCASE_ROOT/../../dir
  is outside the build directory. This is not allowed.
  [1]

  $ cat > dune <<EOF
  > (rule
  >  (targets t)
  >  (deps (sandbox none))
  >  (action
  >   (chdir ../dir
  >    (progn
  >     (no-infer (write-file file hi))
  >     (write-file ../t hi)))))
  > EOF
  $ dune build t
  File "dune", line 5, characters 9-15:
  5 |   (chdir ../dir
               ^^^^^^
  Error: Directory
  $TESTCASE_ROOT/../dir
  is outside the build directory. This is not allowed.
  [1]

Shared action preparation preserves ordinary named rules and alias actions:
working directories are created, environments are retained, and sandboxed
outputs and anonymous-action stamps reach the build directory.

  $ make_dune_project 3.23
  $ cat > dune <<'EOF'
  > (rule
  >  (target prepared-output)
  >  (deps prepared-source)
  >  (action
  >   (chdir action-dir
  >    (setenv PREPARED prepared
  >     (with-stdout-to ../prepared-output
  >      (run sh -c "printf '%s: ' \"$PREPARED\"; cat ../prepared-source"))))))
  > (rule
  >  (alias prepared-alias)
  >  (deps prepared-output)
  >  (action (cat prepared-output)))
  > EOF
  $ echo initial > prepared-source
  $ dune build --sandbox=copy @prepared-alias
  prepared: initial
  $ cat _build/default/prepared-output
  prepared: initial

An unchanged build is cached; changing the input rebuilds both actions.

  $ dune build --sandbox=copy @prepared-alias
  $ echo refreshed > prepared-source
  $ dune build --sandbox=copy @prepared-alias
  prepared: refreshed
  $ cat _build/default/prepared-output
  prepared: refreshed
