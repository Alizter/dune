With no command after the target, dune shell opens Bash. A piped script
sources the same initialization file to test helpers deterministically; the
PTY scenario below exercises actual interactive startup.

  $ make_dune_project 3.26
  $ mkdir home
  $ export HOME=$PWD/home
  $ cat > dune <<'EOF'
  > (rule
  >  (target out)
  >  (action (write-file out "replayed\n")))
  > EOF

Use a private home directory so startup never loads the developer's bashrc.
The run helper is available both as a function and as an executable on PATH;
show_action displays inspection data rather than executing it.

  $ dune shell --sandbox=copy _build/default/out <<'EOF'
  > set -eu
  > . "$DUNE_SHELL/init.bash" >/dev/null
  > type run show_action help >/dev/null
  > test "$(type -P run)" = "$DUNE_SHELL/run"
  > show_action | grep -q write-file
  > echo "helpers: available"
  > run
  > cat out
  > env run
  > cat out
  > EOF
  helpers: available
  replayed
  replayed

On systems with util-linux [script], exercise a real interactive shell through
a pseudo-terminal.  The shell gives each foreground job control of the
terminal, so Ctrl+C and Ctrl-\ stop those jobs without reaching the live Dune
process. Dune's progress line must also stay out of the shell session.
A builtin-only selected action keeps this independent of process policy;
landlock.t covers sessions which inherit write restrictions.

  $ pty_status=0
  $ if script --version 2>&1 | grep -q util-linux; then
  >   export SHELL="$(command -v bash)"
  >   export PTY_ECHO_OFF=$PWD/pty-echo-off
  >   export PTY_INT_READY=$PWD/pty-int-ready
  >   export PTY_INT_SURVIVED=$PWD/pty-int-survived
  >   export PTY_QUIT_READY=$PWD/pty-quit-ready
  >   export PTY_QUIT_SURVIVED=$PWD/pty-quit-survived
  >   {
  >     printf '%s\n' 'stty -echo; : > "$PTY_ECHO_OFF"'
  >     with_timeout dune_cmd wait-for-file-to-appear "$PTY_ECHO_OFF"
  >     printf '%s\n' 'PS1=; PS2=; printf "__ENTERED__\n"'
  >     printf '%s\n' 'sh -c ": > \"$PTY_INT_READY\"; exec sleep 30"'
  >     with_timeout dune_cmd wait-for-file-to-appear "$PTY_INT_READY"
  >     printf '\003'
  >     printf '%s\n' ': > "$PTY_INT_SURVIVED"'
  >     printf '%s\n' 'sh -c ": > \"$PTY_QUIT_READY\"; exec sleep 30"'
  >     with_timeout dune_cmd wait-for-file-to-appear "$PTY_QUIT_READY"
  >     printf '\034'
  >     printf '%s\n' ': > "$PTY_QUIT_SURVIVED"'
  >     printf '%s\n' 'printf "__LEAVING__\n"; exit'
  >   } | with_timeout script -q -e -f -c \
  >       'dune shell --display=progress --sandbox=copy _build/default/out' \
  >       /dev/null >pty.transcript 2>&1
  >   command_status=$?
  >   tr -d '\r' <pty.transcript |
  >     sed -n '/__ENTERED__/,/__LEAVING__/p' >pty-session
  >   if test "$command_status" -eq 0 &&
  >      test -e "$PTY_INT_SURVIVED" &&
  >      test -e "$PTY_QUIT_SURVIVED" &&
  >      grep -q 'session commands' pty.transcript &&
  >      ! grep -q 'Done:' pty-session; then
  >     :
  >   else
  >     pty_status=1
  >     cat pty.transcript >&2
  >   fi
  > fi
  > echo "pty-job-control: checked when supported"
  > test "$pty_status" -eq 0
  pty-job-control: checked when supported
