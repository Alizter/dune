Filesystem sandbox modes determine the execution location and how
dependencies are materialized. OS write restrictions are tested in landlock.t.

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
  >  (action (with-stdout-to out (cat prepared-input))))
  > (rule
  >  (target unrelated)
  >  (action (write-file unrelated unrelated)))
  > EOF
  $ echo prepared > sub/source.txt
  $ dune build --sandbox=none _build/default/sub/unrelated
  $ export ROOT=$PWD

Sandboxed user rules use the mapped rule directory and expose only prepared
dependencies, with the selected copy or link semantics.

  $ for mode in copy symlink hardlink; do
  >   dune shell --sandbox=$mode _build/default/sub/out -- sh -eu -c '
  >     case "$PWD" in
  >       "$ROOT"/_build/.sandbox/*/default/sub) ;;
  >       *) exit 1 ;;
  >     esac
  >     test ! -e unrelated
  >     case "$1" in
  >       copy)
  >         test ! -L prepared-input
  >         test "$(dune_cmd stat hardlinks prepared-input)" -eq 1 ;;
  >       symlink)
  >         test -L prepared-input ;;
  >       hardlink)
  >         test ! -L prepared-input
  >         test "$(dune_cmd stat hardlinks prepared-input)" -gt 1 ;;
  >     esac
  >     printf "%s: " "$1"; cat prepared-input
  >   ' sh "$mode" || exit 1
  > done
  copy: prepared
  symlink: prepared
  hardlink: prepared

A command-line preference cannot opt a user rule out of required sandboxing.

  $ dune shell --sandbox=none _build/default/sub/out -- sh -eu -c '
  > test "$PWD" != "$ROOT/_build/default/sub"
  > test ! -e unrelated
  > echo "required sandbox: retained"
  > '
  required sandbox: retained

Source-copy rules really do run without a sandbox. The session uses the real
build directory, including unrelated artifacts. Replay must preserve the source
path, and its output remains after exit. This rule has a minimal environment,
so resolve inspection tools in the test harness.

  $ SH=$(command -v sh)
  $ CAT=$(command -v cat)
  $ dune shell _build/default/sub/source.txt -- "$SH" -eu -c '
  > test "$PWD" = "$2/_build/default/sub"
  > test -f unrelated
  > "$DUNE_SHELL/dune-run"
  > "$1" source.txt
  > ' sh "$CAT" "$PWD"
  prepared
  $ cat _build/default/sub/source.txt
  prepared
