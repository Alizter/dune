The initiating Dune process owns the build lock and session resources until
the debugging command exits. This remains true on unsuccessful exit.

  $ make_dune_project 3.26
  $ unset DUNE_ACTION_TRACE_DIR
  $ cat > dune <<'EOF'
  > (rule
  >  (target lock-probe)
  >  (action (write-file lock-probe replayed)))
  > (rule
  >  (target trace-output)
  >  (action
  >   (bash
  >    "mkdir -p \"$DUNE_ACTION_TRACE_DIR\"
  >     echo '{}' > \"$DUNE_ACTION_TRACE_DIR/ignored.json\"
  >     printf '%s\\n' \"$DUNE_ACTION_TRACE_DIR\" > trace-output")))
  > EOF

Use a builtin-only action to test the build lock independently of process
write restrictions. A second session must fail specifically because of the
lock, not because an ordinary build was forwarded to the session's non-watch
RPC server.

  $ export ROOT=$PWD
  $ DUNE_BINARY=$(command -v dune)
  $ export DUNE_BINARY
  $ dune shell --sandbox=copy _build/default/lock-probe -- sh -eu -c '
  > test "$(cat "$ROOT/_build/.lock")" = "$PPID"
  > if "$DUNE_BINARY" shell --root "$ROOT" _build/default/lock-probe -- true \
  >      >second.stdout 2>second.stderr; then
  >   exit 1
  > fi
  > if ! grep -q "has locked the build directory" second.stderr; then
  >   cat second.stderr
  >   exit 1
  > fi
  > echo "build lock: held"
  > '
  build lock: held
  $ dune build lock-probe

Ordinary builds clean up their action traces. Replay leaves the session's
trace available for inspection until the debugging command exits.

  $ dune build --sandbox=copy trace-output
  $ test ! -e "$(cat _build/default/trace-output)"

Capture resource paths through stdout rather than writing breadcrumbs outside
the action sandbox. Test teardown after success, nonzero exit, and a signal.
Status formatting itself is covered in exit-status.t.

  $ for outcome in success failure signal; do
  >   status=0
  >   dune shell --sandbox=copy _build/default/trace-output -- sh -eu -c '
  >     test -d "$DUNE_SHELL"
  >     "$DUNE_SHELL/dune-run"
  >     test "$(cat trace-output)" = "$DUNE_ACTION_TRACE_DIR"
  >     test -f "$DUNE_ACTION_TRACE_DIR/ignored.json"
  >     printf "%s\n" "$PWD" "$DUNE_SHELL" "$DUNE_ACTION_TRACE_DIR"
  >     case "$1" in
  >       success) ;;
  >       failure) exit 7 ;;
  >       signal) kill -TERM $$ ;;
  >     esac
  >   ' sh "$outcome" >session-state 2>session.stderr || status=$?
  >   case "$outcome" in
  >     success) test "$status" -eq 0 || exit 1 ;;
  >     failure) test "$status" -eq 7 || exit 1 ;;
  >     signal) test "$status" -eq 1 || exit 1 ;;
  >   esac
  >   test "$(wc -l < session-state)" -eq 3 || exit 1
  >   while IFS= read -r path; do
  >     test ! -e "$path" || exit 1
  >   done < session-state
  >   dune build trace-output || exit 1
  >   printf "%s: resources released\n" "$outcome"
  > done
  success: resources released
  failure: resources released
  signal: resources released
