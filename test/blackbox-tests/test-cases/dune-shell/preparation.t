Dune shell prepares prerequisites but stops before the selected action,
even when the selected target was already up to date.

  $ make_dune_project 3.26
  $ mkdir sub
  $ cat > sub/dune <<'EOF'
  > (rule
  >  (target prepared-input)
  >  (deps source.txt)
  >  (action (copy source.txt prepared-input)))
  > (rule
  >  (target out)
  >  (deps prepared-input)
  >  (action
  >   (progn
  >    (run sh -c "echo selected-action-ran")
  >    (copy prepared-input out))))
  > EOF
  $ echo initial > sub/source.txt

An ordinary build executes the action and leaves a current target. The
action's stdout makes execution observable without writing outside its sandbox.

  $ dune build --sandbox=copy _build/default/sub/out
  selected-action-ran
  $ cat _build/default/sub/out
  initial

Entry clears the existing target but must not print selected-action-ran.

  $ dune shell --sandbox=copy _build/default/sub/out -- sh -eu -c '
  > test ! -e out
  > printf "current-prerequisite: "; cat prepared-input
  > '
  current-prerequisite: initial
  $ test ! -e _build/default/sub/out

Changing the source refreshes the generated prerequisite, still without
executing the selected action.

  $ echo refreshed > sub/source.txt
  $ dune shell --sandbox=copy _build/default/sub/out -- sh -eu -c '
  > test ! -e out
  > printf "refreshed-prerequisite: "; cat prepared-input
  > '
  refreshed-prerequisite: refreshed

A static selected action may have a dynamic prerequisite. Preparing it needs
the normal live build, including its RPC server.

  $ make_dune_project_with_extension 3.26 action-plugin 0.1
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
  $ echo refreshed > dynamic-source
  $ dune shell --sandbox=copy _build/default/static-output -- sh -eu -c '
  > "$DUNE_SHELL/dune-run"
  > cat static-output
  > '
  refreshed
