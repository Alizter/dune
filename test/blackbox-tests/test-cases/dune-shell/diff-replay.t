Replay preserves diff behavior without applying Dune's post-action promotion
effects.

  $ make_dune_project 3.23

  $ cat > dune <<'EOF'
  > (rule
  >  (target corrected)
  >  (action
  >   (progn
  >    (write-file corrected actual)
  >    (diff expected corrected))))
  > EOF
  $ echo expected > expected

Replay of a diff neither changes its source input nor registers a pending
promotion.

  $ dune shell --sandbox=copy _build/default/corrected -- sh -c '
  > if "$DUNE_SHELL/dune-run" >diff.stdout 2>diff.stderr; then
  >   echo "diff-replay: unexpectedly succeeded"
  > else
  >   echo "diff-replay: failed"
  > fi
  > test -s diff.stderr && echo "diff-output: shown"
  > '
  diff-replay: failed
  diff-output: shown
  $ printf "diff-source: "; cat expected
  diff-source: expected
  $ if test -n "$(dune promotion list)"; then
  >   echo "diff-promotion: registered"
  > else
  >   echo "diff-promotion: absent"
  > fi
  diff-promotion: absent

Replay retains the initiating invocation's configured diff command.

  $ export DIFF_MARKER=$PWD/custom-diff-ran
  $ cat > custom-diff <<'EOF'
  > #!/bin/sh
  > : > "$DIFF_MARKER"
  > exit 1
  > EOF
  $ chmod +x custom-diff
  $ dune shell --diff-command "$PWD/custom-diff" --sandbox=copy \
  >   _build/default/corrected -- sh -c '
  > "$DUNE_SHELL/dune-run" >/dev/null 2>&1 || :
  > '
  $ test -e custom-diff-ran && echo "diff-command: preserved"
  diff-command: preserved

Binary directory comparisons are valid since Dune 3.23. BUG: serializing a
cmp action drops its directory-diffs flag, so replay rejects a valid action.

  $ make_dune_project_with_extension 3.23 directory-targets 0.1
  $ mkdir expected-dir
  $ echo matching > expected-dir/input
  $ cat >> dune <<'EOF'
  > (rule
  >  (targets (dir matching-dir))
  >  (deps (source_tree expected-dir))
  >  (action
  >   (progn
  >    (run cp -R expected-dir matching-dir)
  >    (no-infer (cmp expected-dir matching-dir)))))
  > EOF
  $ dune build --sandbox=copy matching-dir
  $ dune shell --sandbox=copy _build/default/matching-dir -- sh -c '
  > "$DUNE_SHELL/dune-run" 2>replay.stderr
  > echo "binary-directory-replay-status: $?"
  > grep "Directory operands" replay.stderr
  > '
  binary-directory-replay-status: 1
  Error: Directory operands in diff actions require at least (lang dune 3.23).
