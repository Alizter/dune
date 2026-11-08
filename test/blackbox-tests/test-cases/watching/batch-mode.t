Failed actions are memoized as reproducible errors. Use an action that increments
a counter before failing to distinguish rerunning the external process from
reraising the cached failure.

In a non-watch build, requesting the same failing action through two aliases in a
single build executes the failed action only once.

  $ make_dune_project 3.22
  $ setup_failing_action_script

  $ counter="$TMPDIR/cached-failed-actions-counter"
  $ rm -f "$counter"
  $ cat > dune <<EOF
  > (rule
  >  (alias fail)
  >  (deps fail.sh)
  >  (action (run sh %{dep:fail.sh} $counter)))
  > (alias
  >  (name a)
  >  (deps (alias fail)))
  > (alias
  >  (name b)
  >  (deps (alias fail)))
  > EOF

  $ dune build @a @b > build.out 2>&1
  [1]
  $ cat "$counter"
  1
  $ print_build_finish_process_counts
  [
    {
      "outcome": "failure",
      "process_count": 2
    }
  ]

An anonymous action's memo identity must include its directory registrations,
even when its literal PATH, action and dependencies have not changed.

  $ mkdir anonymous-watch && cd anonymous-watch
  $ make_dune_project 3.21
  $ cat > helper.sh <<'EOF'
  > #!/bin/sh
  > echo helper
  > EOF
  $ chmod +x helper.sh
  $ echo before > trigger
  $ cat > dune <<EOF
  > (alias (name idle))
  > (rule
  >  (alias probe)
  >  (deps trigger (sandbox always) (universe))
  >  (action
  >   (setenv PATH "$PWD/_build/default/.bin"
  >    (system
  >     "\| if command -v helper >/dev/null; then
  >     "\|   echo 'probe: leaked'
  >     "\| else
  >     "\|   echo 'probe: unavailable'
  >     "\| fi
  >   ))))
  > EOF
  $ mkdir -p _build/default/.bin
  $ cp helper.sh _build/default/.bin/helper
  $ start_dune @idle
  $ build "(alias probe)"
  Success
  $ cat >> dune <<'EOF'
  > (env
  >  (_ (binaries (helper.sh as helper))))
  > EOF
  $ echo after > trigger
  $ build "(alias probe)"
  Success
  $ stop_dune_quiet
  $ grep '^probe:' .#dune-output
  probe: leaked
  probe: leaked

