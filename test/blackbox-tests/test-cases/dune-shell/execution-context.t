The shell receives the prepared execution context. Action-local environment
and directory changes apply only when the captured action is replayed.

  $ make_dune_project 3.26
  $ unset LEADING_ACTION_ENV DUNE_SHELL
  $ cat > dune <<'EOF'
  > (env
  >  (_
  >   (env-vars (DUNE_SHELL_TEST_ENV prepared))))
  > (rule
  >  (target local-tool)
  >  (deps local-tool-source)
  >  (action (copy local-tool-source local-tool)))
  > (rule
  >  (target local-tool-output)
  >  (deps local-tool)
  >  (action
  >   (setenv LEADING_ACTION_ENV visible
  >    (with-stdout-to %{target} (run ./local-tool)))))
  > (rule
  >  (target missing-tool-output)
  >  (deps local-tool)
  >  (action (with-stdout-to %{target} (run not-in-prepared-path))))
  > (rule
  >  (target directory-output)
  >  (action
  >   (chdir action-dir
  >    (with-stdout-to ../directory-output (run pwd)))))
  > (rule
  >  (targets configured configured-cwd)
  >  (action
  >   (progn
  >    (with-stdout-to configured (echo %{profile}))
  >    (with-stdout-to configured-cwd (run pwd)))))
  > EOF
  $ cat > local-tool-source <<'EOF'
  > #!/bin/sh
  > if test -n "${DUNE_SHELL-}"; then session=set; else session=unset; fi
  > printf '%s:%s:%s\n' "$DUNE_SHELL_TEST_ENV" \
  >   "${LEADING_ACTION_ENV-unset}" "$session"
  > EOF
  $ chmod +x local-tool-source

Ordinary execution applies the action's setenv. The shell does not pre-apply
it. Replay inherits shell edits, then applies the action-local override.

  $ dune build --sandbox=copy local-tool-output
  $ cat _build/default/local-tool-output
  prepared:visible:unset
  $ dune shell --sandbox=copy _build/default/local-tool-output -- sh -eu -c '
  > printf "shell: %s:%s\n" "$DUNE_SHELL_TEST_ENV" "${LEADING_ACTION_ENV-unset}"
  > DUNE_SHELL_TEST_ENV=edited LEADING_ACTION_ENV=from-shell \
  >   "$DUNE_SHELL/dune-run"
  > printf "replay: "; cat local-tool-output
  > '
  shell: prepared:unset
  replay: edited:visible:set

Supplied commands interpret relative and empty PATH entries in the session
directory. Captured action programs are not resolved again during replay.

  $ for entry in . ''; do
  >   PATH="$entry:$PATH" dune shell --sandbox=copy \
  >     _build/default/local-tool-output -- local-tool || exit 1
  > done
  prepared:unset:set
  prepared:unset:set
  $ dune shell --sandbox=copy _build/default/missing-tool-output -- sh -eu -c '
  > cp local-tool not-in-prepared-path
  > export PATH="$PWD:$PATH"
  > if "$DUNE_SHELL/dune-run" >missing.stdout 2>missing.stderr; then exit 1; fi
  > grep -q not-in-prepared-path missing.stderr
  > grep -qi "not found" missing.stderr
  > echo "missing program: still unresolved"
  > '
  missing program: still unresolved

Action chdir does not change the session's initial directory.

  $ dune shell --sandbox=copy _build/default/directory-output -- sh -eu -c '
  > test -d action-dir
  > "$DUNE_SHELL/dune-run"
  > test "$(cat directory-output)" = "$PWD/action-dir"
  > echo "action chdir: applied on replay"
  > '
  action chdir: applied on replay

The selected profile and custom build directory survive replay. A workspace
path containing spaces also exercises quoting in the generated runner.

  $ mkdir 'workspace with spaces'
  $ cp dune dune-project 'workspace with spaces'
  $ (
  > cd 'workspace with spaces'
  > ROOT=$PWD dune shell --profile release --build-dir _custom \
  >   --sandbox=copy _custom/default/configured -- sh -eu -c '
  > case "$PWD" in
  >   "$ROOT"/_custom/.sandbox/*/default) ;;
  >   *) exit 1 ;;
  > esac
  > "$DUNE_SHELL/dune-run"
  > printf "profile: "; cat configured; echo
  > test "$(cat configured-cwd)" = "$PWD"
  > echo "replay directory: session directory"
  > '
  > )
  profile: release
  replay directory: session directory

Execution-time temporary-directory injection overrides an action-level
TMPDIR, as in an ordinary build. Replay scratch is cleaned independently of
the live shell's scratch directory.

  $ cat >> dune <<'EOF'
  > (rule
  >  (target prepared-temp)
  >  (action
  >   (setenv TMPDIR action-overridden-temp
  >    (with-stdout-to %{target}
  >     (run sh -c
  >      ": > \"$TMPDIR/replay-write\"; printf '%s\\n' \"$TMPDIR\"")))))
  > EOF
  $ dune build --sandbox=copy prepared-temp
  $ test "$(cat _build/default/prepared-temp)" != action-overridden-temp
  $ test ! -e "$(cat _build/default/prepared-temp)"
  $ dune shell --sandbox=copy _build/default/prepared-temp -- sh -eu -c '
  > : > "$TMPDIR/shell-write"
  > for iteration in 1 2; do
  >   "$DUNE_SHELL/dune-run"
  >   test "$(cat prepared-temp)" != action-overridden-temp
  >   test ! -e "$(cat prepared-temp)"
  > done
  > test -f "$TMPDIR/shell-write"
  > echo "scratch: replay cleaned, shell retained"
  > '
  scratch: replay cleaned, shell retained

Job slots are computed during preparation, including the default one-slot
case. Replay inherits the resulting variable rather than recomputing it.

  $ unset DUNE_JOB_SLOTS
  $ cat >> dune <<'EOF'
  > (rule
  >  (target default-slots)
  >  (action
  >   (with-stdout-to %{target}
  >    (run sh -c "printf '%s\\n' \"${DUNE_JOB_SLOTS-unset}\""))))
  > (rule
  >  (target two-slots)
  >  (job_slots (echo 2))
  >  (action
  >   (with-stdout-to %{target}
  >    (run sh -c "printf '%s\\n' \"${DUNE_JOB_SLOTS-unset}\""))))
  > EOF
  $ dune build -j 4 --sandbox=copy default-slots two-slots
  $ for target in default-slots two-slots; do
  >   expected=$(cat "_build/default/$target")
  >   dune shell -j 4 --sandbox=copy _build/default/$target -- sh -eu -c '
  >     test "$DUNE_JOB_SLOTS" = "$1"
  >     "$DUNE_SHELL/dune-run"
  >     printf "%s: " "$2"; cat "$2"
  >     DUNE_JOB_SLOTS=3 "$DUNE_SHELL/dune-run"
  >     test "$(cat "$2")" = 3
  >   ' sh "$expected" "$target" || exit 1
  > done
  default-slots: 1
  two-slots: 2
