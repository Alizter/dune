Replay recreates action directories after clearing directory targets.
Clearing must preserve the live shell's cwd and must not traverse symlinks.

  $ make_dune_project 3.26
  $ cat > dune <<'EOF'
  > (rule
  >  (targets (dir output-dir))
  >  (action
  >   (progn
  >    (run mkdir -p output-dir)
  >    (chdir output-dir (run sh -c "echo directory-target > value")))))
  > (rule
  >  (targets (dir nested-dir))
  >  (action
  >   (chdir nested-dir/inner (run sh -c "echo nested > value"))))
  > EOF
  $ dune shell --sandbox=copy _build/default/output-dir -- sh -eu -c '
  > "$DUNE_SHELL/dune-run"
  > cat output-dir/value
  > '
  directory-target

A cwd prepared for the action and its ancestors remain usable across repeated
replays. Stale contents, including symlinks, are removed.

  $ export ROOT=$PWD
  $ mkdir _outside
  $ echo keep > _outside/keep
  $ dune shell --sandbox=copy _build/default/nested-dir -- sh -eu -c '
  > cd nested-dir/inner
  > for iteration in 1 2; do
  >   mkdir stale-dir
  >   touch stale-file
  >   ln -s "$ROOT/_outside" outside-link
  >   "$DUNE_SHELL/dune-run"
  >   test ! -e stale-dir
  >   test ! -e stale-file
  >   test ! -L outside-link
  >   test -f "$ROOT/_outside/keep"
  >   printf "nested replay %s: " "$iteration"; cat value
  > done
  > '
  nested replay 1: nested
  nested replay 2: nested

The same holds when the shell enters a directory created by an earlier replay.

  $ dune shell --sandbox=copy _build/default/output-dir -- sh -eu -c '
  > "$DUNE_SHELL/dune-run"
  > cd output-dir
  > for iteration in 1 2; do
  >   "$DUNE_SHELL/dune-run"
  >   printf "moved cwd %s: " "$iteration"; cat value
  > done
  > '
  moved cwd 1: directory-target
  moved cwd 2: directory-target

Replacing an action directory with a symlink must not cause clearing to
traverse its referent. Replay recreates the directory instead.

  $ dune shell --sandbox=copy _build/default/nested-dir -- sh -eu -c '
  > cd nested-dir
  > rmdir inner
  > ln -s "$ROOT/_outside" inner
  > "$DUNE_SHELL/dune-run"
  > test ! -L inner
  > test -f "$ROOT/_outside/keep"
  > cat inner/value
  > '
  nested
