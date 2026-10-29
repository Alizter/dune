The session uses the process policy selected by ordinary action preparation.
A policy, when available, restricts the debugging command and its descendants;
changing the replay environment cannot relax it.

  $ make_dune_project 3.26
  $ unset DUNE_CONFIG__LANDLOCK
  $ if dune internal with-landlock -- true >/dev/null 2>&1; then
  >   POLICY=blocked
  > else
  >   POLICY=wrote
  > fi
  $ export POLICY
  $ export OUTSIDE=$PWD/outside
  $ mkdir "$OUTSIDE"
  $ echo readable > outside/input
  $ cat > probe.sh <<'EOF'
  > if touch "$OUTSIDE/$1" 2>/dev/null; then echo wrote; else echo blocked; fi
  > : > "$TMPDIR/probe-scratch"
  > EOF
  $ cat > dune <<'EOF'
  > (rule
  >  (target report)
  >  (deps probe.sh)
  >  (action (with-stdout-to report (run sh probe.sh action))))
  > (rule
  >  (target builtin-policy)
  >  (action (write-file builtin-policy replayed)))
  > (rule
  >  (target actual)
  >  (action
  >   (progn
  >    (write-file actual actual)
  >    (diff expected actual))))
  > EOF
  $ echo expected > expected

Compare ordinary execution with a session using a custom build directory.
Reads outside the sandbox remain allowed, as do scratch and metadata writes.
On systems without Landlock the same probes observe ordinary unrestricted
behavior instead of silently skipping the session.

  $ dune build --sandbox=copy report
  $ test "$(cat _build/default/report)" = "$POLICY"
  $ dune shell --build-dir _custom --sandbox=copy \
  >   _custom/default/report -- sh -eu -c '
  > test "$(cat "$OUTSIDE/input")" = readable
  > if touch "$OUTSIDE/session" 2>/dev/null; then
  >   result=wrote
  > else
  >   result=blocked
  > fi
  > test "$result" = "$POLICY"
  > : > "$TMPDIR/session-scratch"
  > : > "$DUNE_SHELL/writable"
  > DUNE_CONFIG__LANDLOCK=disabled "$DUNE_SHELL/dune-run"
  > test "$(cat report)" = "$POLICY"
  > '

The external diff command is another descendant of replay and must inherit
the same policy, despite taking the non-promoting diff execution path.

  $ cat > custom-diff <<'EOF'
  > if touch "$OUTSIDE/diff" 2>/dev/null; then
  >   echo wrote > diff-report
  > else
  >   echo blocked > diff-report
  > fi
  > exit 1
  > EOF
  $ dune shell --sandbox=copy --diff-command "sh $PWD/custom-diff" \
  >   _build/default/actual -- sh -eu -c '
  > if "$DUNE_SHELL/dune-run" >diff.stdout 2>diff.stderr; then exit 1; fi
  > test "$(cat diff-report)" = "$POLICY"
  > '
  $ if test "$POLICY" = blocked; then
  >   test ! -e outside/action &&
  >   test ! -e outside/session &&
  >   test ! -e outside/diff
  > fi

Builtin-only actions do not prepare a process policy. A session for such an
action follows that normal decision rather than introducing a different one.

  $ dune shell --sandbox=copy _build/default/builtin-policy -- sh -eu -c '
  > touch "$OUTSIDE/builtin-session"
  > "$DUNE_SHELL/dune-run"
  > test "$(cat builtin-policy)" = replayed
  > '
  $ test -f outside/builtin-session

Explicitly disabling the policy is also preserved. These are policy-selection
tests, not a way to make the other fixtures' forbidden writes succeed.
Re-enabling it in the replay environment must not change the prepared decision.

  $ DUNE_CONFIG__LANDLOCK=disabled dune shell --sandbox=copy \
  >   _build/default/report -- sh -eu -c '
  > DUNE_CONFIG__LANDLOCK=enabled "$DUNE_SHELL/dune-run"
  > test "$(cat report)" = wrote
  > '
  $ cat > policy-config <<'EOF'
  > (lang dune 3.26)
  > (experimental (landlock disabled))
  > EOF
  $ dune shell --config-file policy-config --sandbox=copy \
  >   _build/default/report -- sh -eu -c '
  > DUNE_CONFIG__LANDLOCK=enabled "$DUNE_SHELL/dune-run"
  > test "$(cat report)" = wrote
  > '
