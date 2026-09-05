Explicit sandbox selections retain their normal filesystem semantics.

  $ make_dune_project 3.23

  $ mkdir sub
  $ cat > sub/dune <<'EOF'
  > (rule
  >  (target prepared-input)
  >  (deps source.txt)
  >  (action (copy source.txt prepared-input)))
  > 
  > (rule
  >  (target out)
  >  (deps prepared-input)
  >  (action (with-stdout-to out (cat prepared-input))))
  > EOF
  $ echo prepared > sub/source.txt

Explicit symlink and hardlink selections use the canonical digest path and
give dependencies the selected link semantics.

  $ for mode in symlink hardlink; do
  >   dune shell --sandbox="$mode" _build/default/sub/out -- sh -c '
  >     selected=$(cat "$DUNE_SHELL/sandbox-mode")
  >     echo "$selected"
  >     printf "canonical-path: "; echo "$PWD"
  >     case "$selected" in
  >       symlink)
  >         test -L prepared-input && echo "symlink-semantics: linked" ;;
  >       hardlink)
  >         links=$(dune_cmd stat hardlinks prepared-input)
  >         test "$links" -gt 1 && echo "hardlink-semantics: shared" ;;
  >     esac
  >   ' | censor >"$mode.stdout"
  >   printf "%s-mode: " "$mode"; cat "$mode.stdout"
  > done
  symlink-mode: symlink
  canonical-path: $PWD/_build/.sandbox/$DIGEST/default/sub
  symlink-semantics: linked
  hardlink-mode: hardlink
  canonical-path: $PWD/_build/.sandbox/$DIGEST/default/sub
  hardlink-semantics: shared

Dune 3.25 also applies an OS sandbox policy on supported Linux kernels.
BUG: replay does not preserve that policy, so an action that cannot write
outside the sandbox in an ordinary build can do so through dune-run.

  $ make_dune_project 3.25
  $ unset DUNE_CONFIG__LANDLOCK
  $ export OUTSIDE=$PWD/outside
  $ mkdir "$OUTSIDE"
  $ cat > dune <<'EOF'
  > (rule
  >  (target policy-report)
  >  (action
  >   (with-stdout-to %{target}
  >    (run sh -c
  >     "if touch \"$OUTSIDE/from-action\" 2>/dev/null; then
  >        echo wrote
  >      else
  >        echo blocked
  >      fi"))))
  > EOF
  $ if dune internal with-landlock -- true >/dev/null 2>&1; then
  >   dune build --sandbox=copy _build/default/policy-report &&
  >   test "$(cat _build/default/policy-report)" = blocked &&
  >   dune shell --sandbox=copy _build/default/policy-report -- sh -c '
  >     "$DUNE_SHELL/dune-run" && test "$(cat policy-report)" = wrote
  >   ' &&
  >   test -e outside/from-action
  > fi

The policy must also reach the processes inside compound actions and the
external diff command. Temporary files remain writable under the policy.
BUG: these replay processes currently escape the policy too.

  $ cat > policy-probe <<'EOF'
  > if touch "$OUTSIDE/$1" 2>/dev/null; then echo wrote; else echo blocked; fi
  > : > "$TMPDIR/policy-temp"
  > EOF
  $ echo expected > policy-expected
  $ cat > policy-diff <<'EOF'
  > if touch "$OUTSIDE/diff" 2>/dev/null; then
  >   echo wrote > diff-policy
  > else
  >   echo blocked > diff-policy
  > fi
  > exit 1
  > EOF
  $ cat >> dune <<'EOF'
  > (rule
  >  (targets run-report bash-report system-report pipe-report)
  >  (deps policy-probe)
  >  (action
  >   (progn
  >    (with-stdout-to run-report (run sh policy-probe run))
  >    (with-stdout-to bash-report (bash "sh policy-probe bash"))
  >    (with-stdout-to system-report (system "sh policy-probe system"))
  >    (with-stdout-to pipe-report
  >     (pipe-stdout (run sh policy-probe pipe) (run cat))))))
  > (rule
  >  (target policy-actual)
  >  (action
  >   (progn
  >    (write-file policy-actual actual)
  >    (diff policy-expected policy-actual))))
  > EOF
  $ if dune internal with-landlock -- true >/dev/null 2>&1; then
  >   dune build --sandbox=copy run-report &&
  >   test "$(cat _build/default/*-report | sort -u)" = blocked &&
  >   dune shell --sandbox=copy _build/default/run-report -- sh -c '
  >     "$DUNE_SHELL/dune-run" &&
  >     test "$(cat *-report | sort -u)" = wrote
  >   '
  > fi
  $ if dune internal with-landlock -- true >/dev/null 2>&1; then
  >   dune shell --sandbox=copy --diff-command "sh $PWD/policy-diff" \
  >     _build/default/policy-actual -- sh -c '
  >       "$DUNE_SHELL/dune-run" >diff.stdout 2>diff.stderr
  >       test "$?" -eq 1 && test "$(cat diff-policy)" = wrote
  >     '
  > fi

Disabling the policy in the initiating invocation is preserved even when the
replay is launched with a different value in its environment.

  $ DUNE_CONFIG__LANDLOCK=disabled dune shell --sandbox=copy \
  >   _build/default/policy-report -- sh -c '
  >     DUNE_CONFIG__LANDLOCK=enabled "$DUNE_SHELL/dune-run" &&
  >     test "$(cat policy-report)" = wrote
  >   '
