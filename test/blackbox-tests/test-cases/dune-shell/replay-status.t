Replay preserves raw process output and shell-compatible failure statuses.

  $ make_dune_project 3.23

  $ cat > dune <<'EOF'
  > (rule
  >  (target raw)
  >  (action
  >   (run sh -c "echo raw-stdout; echo raw-stderr >&2; exit 9")))
  > 
  > (rule
  >  (target signaled)
  >  (action (run sh -c "kill -TERM $$")))
  > 
  > (rule
  >  (target accepted-signaled)
  >  (action
  >   (with-accepted-exit-codes 143
  >    (run sh -c "kill -TERM $$"))))
  > 
  > (rule
  >  (target exit-seven)
  >  (action (write-file %{target} seven)))
  > EOF

Replay returns raw stdout, stderr, and non-zero status.

  $ dune shell --sandbox=copy _build/default/raw -- sh -c '
  > "$DUNE_SHELL/dune-run" >replay.stdout 2>replay.stderr
  > status=$?
  > echo "status: $status"
  > printf "stdout: "; cat replay.stdout
  > printf "stderr: "; cat replay.stderr
  > '
  status: 9
  stdout: raw-stdout
  stderr: raw-stderr

Signal termination is returned as the shell-compatible status without a Dune
process diagnostic. A numeric accepted-exit predicate does not accidentally
accept a signal.

  $ for target in signaled accepted-signaled; do
  >   dune shell --sandbox=copy _build/default/$target -- sh -c '
  >     "$DUNE_SHELL/dune-run" >signal.stdout 2>signal.stderr
  >     echo "status: $?"
  >     test ! -s signal.stderr && echo "stderr: empty"
  >   '
  > done
  status: 143
  stderr: empty
  status: 143
  stderr: empty

Command mode propagates the command's own exit status directly, without a
wrapped Dune process error, and still cleans up the sandbox and metadata.

  $ export ROOT=$PWD
  $ dune shell --sandbox=copy _build/default/exit-seven -- sh -c '
  > printf "%s\n" "$PWD" > "$ROOT/nonzero-sandbox"
  > printf "%s\n" "$DUNE_SHELL" > "$ROOT/nonzero-metadata"
  > exit 7
  > ' \
  >   >exit.stdout 2>exit.stderr
  [7]
  $ grep '^Error:' exit.stderr || echo "no wrapped error"
  no wrapped error
  $ test ! -e "$(cat nonzero-sandbox)" && echo "nonzero-sandbox: cleaned"
  nonzero-sandbox: cleaned
  $ test ! -e "$(cat nonzero-metadata)" && echo "nonzero-metadata: cleaned"
  nonzero-metadata: cleaned

Compound accepted-exit predicates round-trip through the replay encoder,
including an empty conjunction that accepts every exit code.

  $ cat >> dune <<'EOF'
  > (rule
  >  (target accepted-or)
  >  (action
  >   (with-accepted-exit-codes (or 0 7)
  >    (run sh -c "touch accepted-or; exit 7"))))
  > (rule
  >  (target accepted-all)
  >  (action
  >   (with-accepted-exit-codes (and)
  >    (run sh -c "touch accepted-all; exit 7"))))
  > EOF
  $ dune build accepted-or accepted-all
  $ for target in accepted-or accepted-all; do
  >   dune shell --sandbox=copy _build/default/$target -- sh -c '
  >     "$DUNE_SHELL/dune-run" >predicate.stdout 2>predicate.stderr
  >     echo "predicate-replay-status: $?"
  >     if test -s predicate.stderr; then
  >       echo "predicate-stderr: nonempty"
  >     else
  >       echo "predicate-stderr: empty"
  >     fi
  >   '
  > done
  predicate-replay-status: 0
  predicate-stderr: empty
  predicate-replay-status: 0
  predicate-stderr: empty

Nested Boolean operators retain their meaning, and an empty disjunction
still rejects every exit code.

  $ cat >> dune <<'EOF'
  > (rule
  >  (target accepted-nested)
  >  (action
  >   (with-accepted-exit-codes (and (or :standard 7) (not 0))
  >    (run sh -c "touch accepted-nested; exit 7"))))
  > (rule
  >  (target rejected-all)
  >  (action
  >   (with-accepted-exit-codes (or)
  >    (run sh -c "exit 7"))))
  > EOF
  $ dune build accepted-nested
  $ for target in accepted-nested rejected-all; do
  >   dune shell --sandbox=copy _build/default/$target -- sh -c '
  >     "$DUNE_SHELL/dune-run"
  >     echo "nested-predicate-status: $?"
  >   '
  > done
  nested-predicate-status: 0
  nested-predicate-status: 7
