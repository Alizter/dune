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
