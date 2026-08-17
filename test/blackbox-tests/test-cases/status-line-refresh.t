The progress status line is refreshed periodically while a build is waiting for
a long-running action. Once the action writes the marker below, it produces no
output and does not exit until released, so no ordinary scheduler event can
redraw the status line.

  $ cat > dune-project <<EOF
  > (lang dune 3.23)
  > EOF

  $ STARTED="$PWD/started"
  $ RELEASE="$PWD/release"
  $ cat > dune <<EOF
  > (rule
  >  (target slow-target)
  >  (action
  >   (progn
  >    (system "touch '$STARTED'; while test ! -f '$RELEASE'; do sleep 0.1; done")
  >    (write-file %{target} done))))
  > EOF

Force the progress display even though stderr is redirected, then wait until
the action is blocked and the initial duration has been rendered.

  $ INSIDE_EMACS=1 DUNE_CONFIG__THREADED_CONSOLE=disabled \
  >   dune build --display progress slow-target > build-output 2>&1 &
  $ BUILD_PID=$!
  $ with_timeout dune_cmd wait-for-file-to-appear "$STARTED"
  $ i=200
  $ INITIAL_DURATION=
  $ while [ "$i" != 0 ]; do
  >   INITIAL_DURATION=$(tr '\r' '\n' < build-output \
  >     | grep -a -E -o "\[[0-9]+\.[0-9]s\]" | awk 'END { print }')
  >   [ -n "$INITIAL_DURATION" ] && break
  >   i=$((i - 1))
  >   sleep 0.01
  > done
  $ if [ -n "$INITIAL_DURATION" ]; then
  >   echo "initial build duration rendered"
  > else
  >   echo "initial build duration missing"
  > fi
  initial build duration rendered

Require two distinct advances. This distinguishes periodic refreshes from a
single unrelated scheduler wakeup.

  $ LAST_DURATION="$INITIAL_DURATION"
  $ REFRESH_COUNT=0
  $ i=200
  $ while [ "$i" != 0 ]; do
  >   CURRENT_DURATION=$(tr '\r' '\n' < build-output \
  >     | grep -a -E -o "\[[0-9]+\.[0-9]s\]" | awk 'END { print }')
  >   if [ -n "$CURRENT_DURATION" ] && [ "$CURRENT_DURATION" != "$LAST_DURATION" ]; then
  >     REFRESH_COUNT=$((REFRESH_COUNT + 1))
  >     LAST_DURATION="$CURRENT_DURATION"
  >     [ "$REFRESH_COUNT" -ge 2 ] && break
  >   fi
  >   i=$((i - 1))
  >   sleep 0.01
  > done
  $ if [ "$REFRESH_COUNT" -ge 2 ]; then
  >   echo "build duration refreshed repeatedly"
  > else
  >   echo "build duration did not refresh repeatedly"
  > fi
  build duration refreshed repeatedly

  $ touch "$RELEASE"
  $ if wait_for_pid_to_exit_with_timeout "$BUILD_PID" 200; then
  >   wait "$BUILD_PID"
  > else
  >   echo "build did not exit"
  > fi
  $ if kill -0 "$BUILD_PID" 2>/dev/null; then
  >   kill "$BUILD_PID"
  >   wait "$BUILD_PID" 2>/dev/null || true
  > fi
