Target selection and unsupported modes for dune shell.

  $ make_dune_project_with_extension 3.26 action-plugin 0.1
  $ cat > dune <<'EOF'
  > (rule
  >  (target ordinary)
  >  (action (write-file %{target} ordinary)))
  > (rule
  >  (alias grouped)
  >  (action (echo alias-action)))
  > (rule
  >  (target dynamic)
  >  (action
  >   (progn
  >    (dynamic-run dune_cmd exit-code 0)
  >    (write-file %{target} dynamic))))
  > EOF

The command after -- is run instead of opening Bash.

  $ dune shell _build/default/ordinary -- \
  >   sh -c 'printf "%s\n" "$1"' sh command-ran
  command-ran

Dynamic selected actions, action runners, and watch mode cannot provide a
single prepared session. Check both rejection and the reason for it.

  $ dune shell _build/default/dynamic -- true >dynamic.stdout 2>dynamic.stderr
  [1]
  $ grep -q 'dynamic actions' dynamic.stderr
  $ dune shell --sandbox-actions _build/default/ordinary -- true \
  >   >runner.stdout 2>runner.stderr
  [1]
  $ grep -q 'external action runners' runner.stderr
  $ dune shell -w _build/default/ordinary -- true >watch.stdout 2>watch.stderr
  [1]
  $ grep -q 'watch mode' watch.stderr

Fully qualified targets remain unambiguous across contexts, including when
resolution produces the same path more than once.

  $ cat > dune-workspace <<'EOF'
  > (lang dune 3.26)
  > (context (default))
  > (context (default (name other)))
  > EOF
  $ dune shell _build/default/ordinary -- true
  $ dune shell _build/other/ordinary -- true

Distinct targets and aliases do not select a single concrete action.

  $ dune shell ordinary -- true
  Error: dune shell requires exactly one concrete target.
  [1]
  $ dune shell @grouped -- true
  Error: dune shell requires a concrete file or directory target.
  Aliases select multiple actions and are not supported yet.
  [1]
