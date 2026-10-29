Debugging-command statuses and replayed-action statuses have different
interfaces. Replay reports ordinary Dune action errors; a supplied command's
numeric exit status is returned directly.

  $ make_dune_project 3.26
  $ cat > dune <<'EOF'
  > (rule
  >  (target raw)
  >  (action
  >   (run sh -c "echo raw-stdout; echo raw-stderr >&2; exit 9")))
  > (rule
  >  (target signaled)
  >  (action (run sh -c "kill -TERM $$")))
  > (rule
  >  (target ordinary)
  >  (action (write-file ordinary ordinary)))
  > (rule
  >  (target accepted)
  >  (action
  >   (with-accepted-exit-codes (or 0 7)
  >    (run sh -c "touch accepted; exit 7"))))
  > EOF

Action stdout and stderr remain visible. An unexpected exit is reported as
an action failure rather than forwarding its numeric exit status.

  $ dune shell --sandbox=copy _build/default/raw -- sh -eu -c '
  > if "$DUNE_SHELL/dune-run" >replay.stdout 2>replay.stderr; then
  >   exit 1
  > else
  >   echo "replay status: $?"
  > fi
  > cat replay.stdout
  > grep -Fx raw-stderr replay.stderr
  > grep -q "Command exited with code 9" replay.stderr
  > '
  replay status: 1
  raw-stdout
  raw-stderr
  $ dune shell --sandbox=copy _build/default/signaled -- sh -eu -c '
  > if "$DUNE_SHELL/dune-run" >signal.stdout 2>signal.stderr; then
  >   exit 1
  > else
  >   echo "replay status: $?"
  > fi
  > grep -q "Command got signal TERM" signal.stderr
  > '
  replay status: 1

An accepted nonzero action exit succeeds without a diagnostic.

  $ dune shell --sandbox=copy _build/default/accepted -- sh -eu -c '
  > "$DUNE_SHELL/dune-run" >accepted.stdout 2>accepted.stderr
  > test -f accepted
  > test ! -s accepted.stderr
  > '

A supplied command's nonzero exit is returned without an action-error wrapper.
Successful and numeric-exit command modes add no startup messages.

  $ dune shell _build/default/ordinary -- sh -c 'exit 7' \
  >   >exit.stdout 2>exit.stderr
  [7]
  $ test ! -s exit.stdout
  $ test ! -s exit.stderr
  $ dune shell _build/default/ordinary -- true >quiet.stdout 2>quiet.stderr
  $ test ! -s quiet.stdout
  $ test ! -s quiet.stderr

Signals in the supplied command use ordinary command diagnostics. Explicit
command-line diagnostics remain available.

  $ dune shell _build/default/ordinary -- sh -c 'kill -TERM $$' \
  >   >signal.stdout 2>signal.stderr
  [1]
  $ cat signal.stderr
  Command got signal TERM.
  $ dune shell --always-show-command-line _build/default/ordinary \
  >   -- sh -c 'kill -TERM $$' >detailed.stdout 2>detailed.stderr
  [1]
  $ grep -Fq 'kill -TERM' detailed.stderr
  $ grep -Fq 'Command got signal TERM.' detailed.stderr
