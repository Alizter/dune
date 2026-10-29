Replay a compiler-generated action and a link action, not just user rules.
The compilation session starts in the target directory; the captured action
must still apply its own chdir before invoking the compiler.

  $ make_dune_project 3.26
  $ cat > dune <<'EOF'
  > (executable
  >  (name main))
  > EOF
  $ cat > main.ml <<'EOF'
  > let () = print_endline "linked by replay"
  > EOF

  $ dune shell --sandbox=copy \
  >   _build/default/.main.eobjs/byte/dune__exe__Main.cmo -- sh -eu -c '
  > "$DUNE_SHELL/dune-run"
  > test -f dune__exe__Main.cmo
  > echo compiled
  > '
  compiled

  $ dune shell --sandbox=copy _build/default/main.exe -- sh -eu -c '
  > "$DUNE_SHELL/dune-run"
  > ./main.exe
  > '
  linked by replay
