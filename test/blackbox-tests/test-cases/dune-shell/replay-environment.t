The shell and replay share Dune's prepared action environment while keeping
shell-control variables out of the replayed action.

  $ make_dune_project 3.23

  $ cat > dune <<'EOF'
  > (env
  >  (_
  >   (env-vars (DUNE_SHELL_TEST_ENV prepared))))
  > 
  > (rule
  >  (target action-env)
  >  (action
  >   (with-stdout-to %{target}
  >    (run sh -c
  >     "if test -n \"${DUNE_SHELL+x}\"; then
  >        echo present
  >      else
  >        echo absent
  >      fi"))))
  > 
  > (rule
  >  (target prepared-env)
  >  (action
  >   (with-stdout-to %{target}
  >    (run sh -c "printf '%s\\n' \"$DUNE_SHELL_TEST_ENV\""))))
  > 
  > (rule
  >  (target prepared-temp)
  >  (action
  >   (setenv TMPDIR action-overridden-temp
  >    (with-stdout-to %{target} (run sh -c "printf '%s\\n' \"$TMPDIR\"")))))
  > EOF

Shell-control variables are present for debugging but absent from the action;
ordinary action-environment layers are present in both.

  $ dune shell --sandbox=copy _build/default/action-env -- sh -c '
  > test -n "$DUNE_SHELL" && echo "debug-command: DUNE_SHELL is set"
  > "$DUNE_SHELL/dune-run"
  > printf "action: DUNE_SHELL is "; cat action-env
  > '
  debug-command: DUNE_SHELL is set
  action: DUNE_SHELL is absent

  $ dune shell --sandbox=copy _build/default/prepared-env -- sh -c '
  > printf "debug-command: %s\n" "$DUNE_SHELL_TEST_ENV"
  > "$DUNE_SHELL/dune-run"
  > printf "replayed-action: "; cat prepared-env
  > '
  debug-command: prepared
  replayed-action: prepared

Dune's execution-time temporary directory injection takes precedence over an
action-level [setenv TMPDIR], just as it does for an ordinary action process.
The shell and replay use that same initiating-build directory.

  $ dune shell --sandbox=copy _build/default/prepared-temp -- sh -c '
  > prepared_temp=$TMPDIR
  > test -n "$TMPDIR" &&
  >   test "$TMPDIR" != action-overridden-temp && echo "shell-temp: exact"
  > "$DUNE_SHELL/dune-run"
  > test "$(cat prepared-temp)" = "$prepared_temp" && echo "replay-temp: exact"
  > '
  shell-temp: exact
  replay-temp: exact

The direct-process environment includes execution-time injection too, after
applying leading setenv wrappers, just as the interpreter does before launching
the process.

  $ dune shell --sandbox=copy _build/default/prepared-temp -- sh -c '
  > "$DUNE_SHELL/dune-run"
  > if grep -Fx "TMPDIR=$(cat prepared-temp)" "$DUNE_SHELL/command.env" >/dev/null; then
  >   echo "metadata-temp: matches replay"
  > else
  >   echo "metadata-temp: differs from replay"
  > fi
  > '
  metadata-temp: matches replay

Bash actions receive the same final environment in their process metadata.

  $ cat >> dune <<'EOF'
  > (rule
  >  (target prepared-bash-temp)
  >  (action
  >   (setenv TMPDIR action-overridden-temp
  >    (bash "printf '%s\\n' \"$TMPDIR\" > prepared-bash-temp"))))
  > EOF
  $ dune shell --sandbox=copy _build/default/prepared-bash-temp -- sh -c '
  > "$DUNE_SHELL/dune-run" &&
  > grep -Fx "TMPDIR=$(cat prepared-bash-temp)" \
  >   "$DUNE_SHELL/command.env" >/dev/null &&
  > echo "bash-metadata-temp: matches replay"
  > '
  bash-metadata-temp: matches replay

Normal action execution and shell preparation share the action trace
directory injection.

  $ unset DUNE_ACTION_TRACE_DIR
  $ cat >> dune <<'EOF'
  > (rule
  >  (target trace-env)
  >  (action
  >   (with-stdout-to %{target}
  >    (run sh -c
  >     "if test -n \"${DUNE_ACTION_TRACE_DIR:-}\"; then
  >        echo present
  >      else
  >        echo absent
  >      fi"))))
  > EOF
  $ dune build --sandbox=copy trace-env
  $ printf "trace-env-normal: "; cat _build/default/trace-env
  trace-env-normal: present
  $ dune shell --sandbox=copy _build/default/trace-env -- sh -c '
  > "$DUNE_SHELL/dune-run" && printf "trace-env-replay: " && cat trace-env
  > '
  trace-env-replay: present

Trace writes are permitted with the process sandbox policy. Ordinary builds
collect them, whereas a shell leaves them available until the session exits.
Both successful and unsuccessful sessions clean up without collecting them.

  $ make_dune_project 3.25
  $ export ROOT=$PWD
  $ cat >> dune <<'EOF'
  > (rule
  >  (target trace-output)
  >  (action
  >   (bash
  >    "mkdir -p \"$DUNE_ACTION_TRACE_DIR\"
  >     echo '{}' > \"$DUNE_ACTION_TRACE_DIR/ignored.json\"
  >     printf '%s\\n' \"$DUNE_ACTION_TRACE_DIR\" > trace-output")))
  > EOF
  $ dune build --sandbox=copy trace-output
  $ test ! -e "$(cat _build/default/trace-output)" &&
  >   echo "ordinary-trace: cleaned"
  ordinary-trace: cleaned
  $ for status in 0 5; do
  >   if dune shell --sandbox=copy _build/default/trace-output -- sh -c '
  >     "$DUNE_SHELL/dune-run" &&
  >     test "$(cat trace-output)" = "$DUNE_ACTION_TRACE_DIR" &&
  >     test -f "$DUNE_ACTION_TRACE_DIR/ignored.json" &&
  >     grep -Fx "DUNE_ACTION_TRACE_DIR=$DUNE_ACTION_TRACE_DIR" \
  >       "$DUNE_SHELL/command.env" >/dev/null &&
  >     echo "session-trace: available"
  >     printf "%s\n" "$DUNE_ACTION_TRACE_DIR" > "$ROOT/replay-trace-dir"
  >     exit "$1"
  >   ' sh "$status"; then
  >     echo "session-status: 0"
  >   else
  >     echo "session-status: $?"
  >   fi
  >   test ! -e "$(cat replay-trace-dir)" && echo "session-trace: cleaned"
  > done
  session-trace: available
  session-status: 0
  session-trace: cleaned
  session-trace: available
  session-status: 5
  session-trace: cleaned
