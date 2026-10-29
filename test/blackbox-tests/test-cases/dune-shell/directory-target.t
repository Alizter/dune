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

A leading chdir can place the live shell inside a directory target. Replay
clears the contents while keeping the shell's working directory inode.

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
  relative-value: present
  absolute-value: present

A nested working directory and its ancestors remain usable across repeated
replays. Other target contents are removed without following symlinks.

  $ export ROOT=$PWD
  $ mkdir _outside
  $ echo keep > _outside/keep
  $ cat >> dune <<'EOF'
  > (rule
  >  (targets (dir nested-dir))
  >  (action
  >   (chdir nested-dir/inner (run sh -c "echo nested > value"))))
  > EOF
  $ dune shell --sandbox=copy _build/default/nested-dir -- sh -c '
  > for iteration in 1 2; do
  >   mkdir stale-dir
  >   touch stale-file
  >   ln -s "$ROOT/_outside" outside-link
  >   "$DUNE_SHELL/dune-run" &&
  >   test ! -e stale-dir && test ! -e stale-file &&
  >   test ! -e outside-link && test -f "$ROOT/_outside/keep" &&
  >   printf "nested-replay-$iteration: " && cat value
  > done
  > '
  nested-replay-1: nested
  nested-replay-2: nested

The invoking shell can also move into a directory target after session entry.
Replay preserves this cwd, not just the initially prepared one.

  $ dune shell --sandbox=copy _build/default/output-dir -- sh -c '
  > cd output-dir
  > for iteration in 1 2; do
  >   "$DUNE_SHELL/dune-run" &&
  >   printf "moved-cwd-$iteration: " && cat value
  > done
  > '
  moved-cwd-1: directory-target
  moved-cwd-2: directory-target

If the initial cwd is replaced with a symlink after the shell leaves it,
clearing must unlink the symlink rather than traverse its referent.

  $ dune shell --sandbox=copy _build/default/nested-dir -- sh -c '
  > cd ..
  > rmdir inner
  > ln -s "$ROOT/_outside" inner
  > "$DUNE_SHELL/dune-run" &&
  > test ! -L inner && test -f "$ROOT/_outside/keep" &&
  > printf "replaced-cwd: " && cat inner/value
  > '
  replaced-cwd: nested
