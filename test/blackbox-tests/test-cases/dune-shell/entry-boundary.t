`dune shell` drives the ordinary live build to the selected rule's action
boundary: dependencies are built and the declared targets are removed, but
the selected action itself is not executed.

  $ make_dune_project 3.23

  $ mkdir sub
  $ cat > sub/dune <<'EOF'
  > (rule
  >  (target prepared-input)
  >  (deps source.txt)
  >  (action (copy source.txt prepared-input)))
  > 
  > (rule
  >  (targets out action-cwd)
  >  (deps prepared-input)
  >  (action
  >   (progn
  >    (with-stdout-to out (cat prepared-input))
  >    (with-stdout-to action-cwd (run pwd))
  >    (run sh -c ": > \"$DUNE_SHELL_ENTRY_BEACON\""))))
  > EOF

  $ echo initial > sub/source.txt
  $ export DUNE_SHELL_ENTRY_BEACON=$PWD/selected-action-ran
  $ dune build --sandbox=copy _build/default/sub/out
  $ rm selected-action-ran

Even when the selected target and all of its prerequisites are current, entry
must still reach its action boundary, remove its old targets, and stop before
executing the selected action.

  $ dune shell --sandbox=copy _build/default/sub/out -- sh -c '
  > test ! -e out && test ! -e action-cwd && echo "current-target: suspended"
  > test ! -e "$DUNE_SHELL_ENTRY_BEACON" && echo "current-side-effect: suspended"
  > printf "current-dependency: "; cat prepared-input
  > '
  current-target: suspended
  current-side-effect: suspended
  current-dependency: initial

Now change an input of the generated prerequisite. Entry must rebuild that
prerequisite and again stop at the selected action boundary.

  $ echo refreshed > sub/source.txt
  $ dune shell --sandbox=copy _build/default/sub/out -- sh -c '
  > test ! -e out && test ! -e action-cwd && echo "refreshed-target: suspended"
  > test ! -e "$DUNE_SHELL_ENTRY_BEACON" && echo "refreshed-side-effect: suspended"
  > printf "refreshed-dependency: "; cat prepared-input
  > '
  refreshed-target: suspended
  refreshed-side-effect: suspended
  refreshed-dependency: refreshed

A selected static action may have a dynamic prerequisite. On the RPC action
plugin implementation, prerequisite execution needs a live RPC server too.
BUG: shell preparation does not start that server.

  $ make_dune_project_with_extension 3.23 action-plugin 0.1
  $ export ACTION_PLUGIN_HELPER="$PWD/../../utils/action_plugin_helper.exe"
  $ cat > dune <<'EOF'
  > (rule
  >  (target dynamic-input)
  >  (deps dynamic-source)
  >  (action
  >   (progn
  >    (dynamic-run %{env:ACTION_PLUGIN_HELPER=unset} noop)
  >    (copy dynamic-source dynamic-input))))
  > (rule
  >  (target static-output)
  >  (deps dynamic-input)
  >  (action (copy dynamic-input static-output)))
  > EOF
  $ echo initial > dynamic-source
  $ dune build --sandbox=copy static-output
  $ cat _build/default/static-output
  initial
  $ echo refreshed > dynamic-source
  $ if dune shell --sandbox=copy _build/default/static-output -- sh -c '
  >   "$DUNE_SHELL/dune-run" && cat static-output
  > ' >dynamic.stdout 2>dynamic.stderr; then
  >   printf "dynamic-prerequisite: "; cat dynamic.stdout
  > else
  >   echo "dynamic-prerequisite: failed"
  > fi
  dynamic-prerequisite: failed
  $ if test ! -s dynamic.stderr; then
  >   echo "dynamic-diagnostic: empty"
  > elif grep -qi rpc dynamic.stderr; then
  >   echo "dynamic-diagnostic: RPC unavailable"
  > else
  >   echo "dynamic-diagnostic: unexpected"
  > fi
  dynamic-diagnostic: RPC unavailable
