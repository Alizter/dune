Replay executes actions without publishing their results through Dune's
normal output extraction, diff promotion, or patch-back finalization.

  $ make_dune_project 3.26
  $ cat > dune <<'EOF'
  > (rule
  >  (target out)
  >  (action (write-file out replayed)))
  > (rule
  >  (target corrected)
  >  (action
  >   (progn
  >    (write-file corrected actual)
  >    (diff expected corrected))))
  > EOF
  $ echo expected > expected

An output exists in the live copy sandbox but is not extracted on exit.

  $ dune shell --sandbox=copy _build/default/out -- sh -eu -c '
  > "$DUNE_SHELL/dune-run"
  > cat out
  > '
  replayed
  $ test ! -e _build/default/out

A failed diff is still displayed, but neither changes the source nor registers
a promotion.

  $ dune shell --sandbox=copy _build/default/corrected -- sh -eu -c '
  > if "$DUNE_SHELL/dune-run" >diff.stdout 2>diff.stderr; then exit 1; fi
  > test -s diff.stderr
  > test "$(cat corrected)" = actual
  > echo "diff: failed with output"
  > '
  diff: failed with output
  $ cat expected
  expected
  $ dune promotion list

The configured diff command is retained, even with auto-promotion enabled.
Its marker belongs inside the action sandbox, not in the source tree.

  $ export DIFF_MARKER=custom-diff-ran
  $ cat > custom-diff <<'EOF'
  > : > "$DIFF_MARKER"
  > exit 1
  > EOF
  $ dune shell --auto-promote --sandbox=copy \
  >   --diff-command "sh \"$PWD/custom-diff\"" \
  >   _build/default/corrected -- sh -eu -c '
  > if "$DUNE_SHELL/dune-run" >diff.stdout 2>diff.stderr; then exit 1; fi
  > test -f custom-diff-ran
  > echo "configured diff: ran"
  > '
  configured diff: ran
  $ cat expected
  expected
  $ dune promotion list

Patch-back replay keeps edits, additions, and deletions in the session.
Neither normal exit nor auto-promotion publishes those changes.

  $ cat >> dune <<'EOF'
  > (rule
  >  (target patch-out)
  >  (deps patch-edited patch-removed (sandbox patch_back_source_tree))
  >  (action
  >   (progn
  >    (system "echo changed > patch-edited")
  >    (system "echo new > patch-added")
  >    (system "rm -f patch-removed")
  >    (write-file patch-out replayed))))
  > EOF
  $ echo original > patch-edited
  $ echo original > patch-removed
  $ for option in '' --auto-promote; do
  >   dune shell $option _build/default/patch-out -- sh -eu -c '
  >     "$DUNE_SHELL/dune-run"
  >     test "$(cat patch-edited)" = changed
  >     test "$(cat patch-added)" = new
  >     test ! -e patch-removed
  >     test "$(cat patch-out)" = replayed
  >   ' || exit 1
  >   test "$(cat patch-edited)" = original || exit 1
  >   test "$(cat patch-removed)" = original || exit 1
  >   test ! -e patch-added || exit 1
  >   test ! -e _build/default/patch-out || exit 1
  >   dune promotion list || exit 1
  > done
