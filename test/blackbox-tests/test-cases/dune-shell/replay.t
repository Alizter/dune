Replay executes the captured action against the live sandbox, without
rebuilding its prerequisites or interpreting the action's inspection text.

  $ make_dune_project 3.26
  $ cat > dune <<'EOF'
  > (rule
  >  (target prepared-input)
  >  (action (write-file prepared-input "prepared\n")))
  > (rule
  >  (target out)
  >  (deps prepared-input (universe))
  >  (action (run sh -eu -c "test ! -e out; cp prepared-input out")))
  > EOF

A universe dependency contributes no files. Editing the prepared dependency
inside the copy sandbox must affect replay, not trigger another build.
The action refuses to overwrite an existing target, so the second replay
also establishes that targets are cleared between runs.

  $ dune shell --sandbox=copy _build/default/out -- sh -eu -c '
  > printf "inspection only" > "$DUNE_SHELL/action.sexp"
  > for value in first second; do
  >   printf "%s\n" "$value" > prepared-input
  >   "$DUNE_SHELL/dune-run"
  >   cat out
  > done
  > '
  first
  second
  $ cat _build/default/prepared-input
  prepared

Static extensions nested in compound actions retain their executable payload.
Their inputs remain editable within the sandbox, and failures remain ordinary
action errors.

  $ echo '(a    b)' > formatter-input
  $ cat >> dune <<'EOF'
  > (rule
  >  (target formatted)
  >  (action
  >   (progn
  >    (echo before-extension)
  >    (format-dune-file formatter-input formatted))))
  > EOF
  $ dune shell --sandbox=copy _build/default/formatted -- sh -eu -c '
  > "$DUNE_SHELL/dune-run" >extension.stdout
  > grep -Fx before-extension extension.stdout
  > cat formatted
  > rm formatter-input
  > printf "(changed)\n" > formatter-input
  > "$DUNE_SHELL/dune-run" >extension.stdout
  > cat formatted
  > rm formatter-input
  > printf "(" > formatter-input
  > if "$DUNE_SHELL/dune-run" >extension.stdout 2>extension.stderr; then
  >   exit 1
  > fi
  > grep -qi "unclosed parenthesis" extension.stderr
  > echo "extension failure: action error"
  > '
  before-extension
  (a b)
  (changed)
  extension failure: action error

Malformed session data must fail before clearing targets. Exercise invalid
csexp, an invalid value, and an invalid marshalled snapshot without depending
on Marshal's binary layout or the wording of an internal error.

  $ dune shell --sandbox=copy _build/default/out -- sh -eu -c '
  > cp "$DUNE_SHELL/replay.csexp" valid-session
  > printf untouched > out
  > for invalid in malformed "()" "3:bad"; do
  >   printf "%s" "$invalid" > "$DUNE_SHELL/replay.csexp"
  >   if "$DUNE_SHELL/dune-run" >invalid.stdout 2>invalid.stderr; then
  >     exit 1
  >   fi
  >   test -s invalid.stderr
  >   test "$(cat out)" = untouched
  > done
  > echo "invalid replay: targets untouched"
  > cp valid-session "$DUNE_SHELL/replay.csexp"
  > "$DUNE_SHELL/dune-run"
  > cat out
  > '
  invalid replay: targets untouched
  prepared

External paths retain their filesystem meaning: lexical normalization of
symlink/.. would select the wrong input.

  $ mkdir -p _ext/real/child
  $ ln -s real/child _ext/link
  $ echo correct > _ext/real/input
  $ echo wrong > _ext/input
  $ export INPUT="$PWD/_ext/link/../input"
  $ cat >> dune <<'EOF'
  > (rule
  >  (target external-input)
  >  (action (copy %{env:INPUT=unset} external-input)))
  > EOF
  $ dune shell --sandbox=copy _build/default/external-input -- sh -eu -c '
  > "$DUNE_SHELL/dune-run"
  > cat external-input
  > '
  correct
