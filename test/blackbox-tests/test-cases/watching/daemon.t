Daemon mode is opt-in. Without configuration, builds do not leave a server.

  $ unset DUNE_TRACE
  $ make_simple_rpc_watch_project
  $ dune build x
  $ dune rpc ping
  Error: RPC server not running.
  [1]

Enable the daemon, rebuild changed inputs, and reuse it even if automatic startup
is subsequently disabled. Subshells stop at the first failure and clean up servers.

  $ mkdir workspace
  $ (
  > set -e
  > cd workspace
  > trap 'dune shutdown >/dev/null 2>&1 || :' EXIT
  > make_dune_project 3.23
  > cat > dune-workspace <<'EOF'
  > (lang dune 3.25)
  > (daemon enabled)
  > EOF
  > cat > dune <<'EOF'
  > (rule
  >  (target x)
  >  (deps input)
  >  (action
  >   (progn
  >    (run sh -c "echo 'action output'")
  >    (copy input %{target}))))
  > EOF
  > echo first > input
  > "$timeout" 10 dune build x
  > cat _build/default/x
  > dune rpc ping
  > daemon_pid=$(cat _build/.lock)
  > if ! wait_for_line_with_timeout _build/.daemon.log 'action output' 200; then
  >   cat _build/.daemon.log
  >   exit 1
  > fi
  > grep '^action output$' _build/.daemon.log
  > echo second > input
  > "$timeout" 10 dune build x
  > cat _build/default/x
  > test "$daemon_pid" = "$(cat _build/.lock)"
  > cat > dune-workspace <<'EOF'
  > (lang dune 3.25)
  > (daemon disabled)
  > EOF
  > "$timeout" 10 dune build x
  > test "$daemon_pid" = "$(cat _build/.lock)"
  > DUNE_PID=$daemon_pid
  > stop_dune_quiet
  > dune build x
  > )
  Success
  first
  Server appears to be responding normally
  action output
  Success
  second
  Success
  action output

The launcher preserves the selected root, build directory, and environment.

  $ mkdir elsewhere
  $ (
  > set -e
  > cd elsewhere
  > trap 'dune shutdown --root project --build-dir _other >/dev/null 2>&1 || :' EXIT
  > mkdir project
  > echo '(lang dune 3.23)' > project/dune-project
  > cat > project/dune-workspace <<'EOF'
  > (lang dune 3.25)
  > (daemon enabled)
  > EOF
  > cat > project/dune <<'EOF'
  > (rule (target x) (action (write-file %{target} %{env:DAEMON_VALUE=missing})))
  > EOF
  > DAEMON_VALUE=inherited "$timeout" 10 dune build --root project --build-dir _other x
  > cat project/_other/default/x
  > echo
  > dune rpc ping --root project --build-dir _other
  > DUNE_PID=$(cat project/_other/.lock)
  > dune shutdown --root project --build-dir _other
  > wait_for_dune_exit_with_timeout
  > test ! -e project/_build/.rpc/dune
  > )
  Entering directory 'project'
  Success
  Leaving directory 'project'
  inherited
  Server appears to be responding normally

Workspace configuration overrides inherited file configuration. Internal
configuration can explicitly override the workspace setting in turn.

  $ mkdir config
  $ (
  > set -e
  > cd config
  > trap 'dune shutdown >/dev/null 2>&1 || :' EXIT
  > make_simple_rpc_watch_project
  > mkdir -p "$XDG_CONFIG_HOME/dune"
  > cat > "$XDG_CONFIG_HOME/dune/config" <<'EOF'
  > (lang dune 3.25)
  > (daemon enabled)
  > EOF
  > cat > dune-workspace <<'EOF'
  > (lang dune 3.25)
  > (daemon disabled)
  > EOF
  > dune build --config-file "$XDG_CONFIG_HOME/dune/config" x
  > test ! -e _build/.rpc/dune
  > DUNE_CONFIG__DAEMON=enabled "$timeout" 10 dune build x
  > dune rpc ping
  > DUNE_PID=$(cat _build/.lock)
  > stop_dune_quiet
  > rm dune-workspace
  > DUNE_CONFIG__DAEMON=disabled dune build --config-file "$XDG_CONFIG_HOME/dune/config" x
  > test ! -e _build/.rpc/dune
  > env -u INSIDE_DUNE "$timeout" 10 dune build --root . --no-print-directory x
  > dune rpc ping
  > DUNE_PID=$(cat _build/.lock)
  > stop_dune_quiet
  > )
  Success
  Server appears to be responding normally
  Warning:
  Your build request is being forwarded to a running Dune instance. Note that
  certain command line arguments may be ignored.
  Success
  Server appears to be responding normally
  $ rm -f "$XDG_CONFIG_HOME/dune/config"

Runtest shares startup, but explicit watch mode remains a foreground server.

  $ mkdir runtest
  $ (
  > set -e
  > cd runtest
  > trap 'dune shutdown >/dev/null 2>&1 || :' EXIT
  > make_dune_project 3.23
  > cat > dune-workspace <<'EOF'
  > (lang dune 3.25)
  > (daemon enabled)
  > EOF
  > echo '(rule (alias runtest) (action (write-file tested ok)))' > dune
  > "$timeout" 10 dune runtest
  > cat _build/default/tested
  > DUNE_PID=$(cat _build/.lock)
  > stop_dune_quiet
  > rm _build/.daemon.log
  > start_dune
  > test ! -e _build/.daemon.log
  > stop_dune_quiet
  > )
  Success
  ok

Two simultaneous cold clients converge on one server without building an
unrequested default target.

  $ mkdir simultaneous
  $ (
  > set -e
  > cd simultaneous
  > trap 'dune shutdown >/dev/null 2>&1 || :' EXIT
  > make_dune_project 3.23
  > cat > dune-workspace <<'EOF'
  > (lang dune 3.25)
  > (daemon enabled)
  > EOF
  > cat > dune <<'EOF'
  > (rule (target x) (action (write-file %{target} x)))
  > (rule (target y) (action (write-file %{target} y)))
  > (rule (target unexpected) (action (write-file %{target} unexpected)))
  > EOF
  > "$timeout" 10 dune build x > .#x-output 2>&1 &
  > x_pid=$!
  > "$timeout" 10 dune build y > .#y-output 2>&1 &
  > y_pid=$!
  > result=0
  > wait "$x_pid" || result=1
  > wait "$y_pid" || result=1
  > cat .#x-output .#y-output
  > test "$result" = 0
  > test ! -e _build/default/unexpected
  > DUNE_PID=$(cat _build/.lock)
  > stop_dune_quiet
  > )
  Success
  Success

A child which fails before RPC startup must not leave its client retrying forever.

  $ mkdir failure
  $ (
  > set -e
  > cd failure
  > make_simple_rpc_watch_project
  > mkdir _build
  > : > _build/.sync
  > cat > dune-workspace <<'EOF'
  > (lang dune 3.25)
  > (daemon enabled)
  > EOF
  > "$timeout" 10 dune build x
  > )
  Error: Dune daemon exited before becoming ready.
  Hint: See _build/.daemon.log for daemon output.
  [1]

A live server can take time to answer. Startup and response waiting have separate
status lines. Internal configuration also works without the scalar stanza.

  $ mkdir response
  $ (
  > set -e
  > cd response
  > trap 'dune shutdown >/dev/null 2>&1 || :' EXIT
  > make_dune_project 3.23
  > cat > dune-workspace <<'EOF'
  > (lang dune 3.25)
  > (experimental (daemon enabled))
  > EOF
  > cat > dune <<'EOF'
  > (rule
  >  (target x)
  >  (action (progn (run sh -c "sleep 1") (write-file %{target} ok))))
  > EOF
  > INSIDE_EMACS=1 DUNE_CONFIG__THREADED_CONSOLE=disabled \
  >   "$timeout" 10 dune build --display progress x > .#client-output 2>&1
  > tr '\r' '\n' < .#client-output | grep 'Waiting for RPC server to start' | uniq
  > tr '\r' '\n' < .#client-output | grep 'Connected to RPC server' | uniq
  > cat _build/default/x
  > DUNE_PID=$(cat _build/.lock)
  > stop_dune_quiet
  > )
  Waiting for RPC server to start
  Connected to RPC server
  ok
