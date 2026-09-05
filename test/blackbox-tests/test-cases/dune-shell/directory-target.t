Directory targets and action [chdir] paths are recreated after replay clears
the target.

  $ make_dune_project_with_extension 3.23 directory-targets 0.1

  $ cat > dune <<'EOF'
  > (rule
  >  (targets (dir output-dir))
  >  (action
  >   (progn
  >    (run mkdir -p output-dir)
  >    (chdir output-dir (run sh -c "echo directory-target > value")))))
  > EOF

  $ dune shell --sandbox=copy _build/default/output-dir -- sh -c '
  > "$DUNE_SHELL/dune-run"
  > printf "directory-target: "; cat output-dir/value
  > '
  directory-target: directory-target

BUG: a leading chdir can place the live shell inside a directory target.
Replay recreates the target's pathname but leaves the shell in a deleted inode.

  $ cat >> dune <<'EOF'
  > (rule
  >  (targets (dir leading-dir))
  >  (action (chdir leading-dir (run sh -c "echo value > value"))))
  > EOF
  $ dune shell --sandbox=copy _build/default/leading-dir -- sh -c '
  > "$DUNE_SHELL/dune-run" &&
  > if test -f value; then
  >   echo "relative-value: present"
  > else
  >   echo "relative-value: absent"
  > fi
  > test -f "$PWD/value" && echo "absolute-value: present"
  > '
  relative-value: absent
  absolute-value: present
