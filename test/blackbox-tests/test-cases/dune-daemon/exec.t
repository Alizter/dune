Test that daemon mode works with exec command.

Create a simple project with daemon enabled in the workspace:

  $ cat > dune-workspace <<EOF
  > (lang dune 3.21)
  > (daemon (enabled true))
  > EOF

  $ cat > dune-project <<EOF
  > (lang dune 3.21)
  > EOF

  $ cat > dune <<EOF
  > (executable (name foo))
  > EOF

  $ cat > foo.ml <<EOF
  > let () = print_endline "hello from exec"
  > EOF

Run exec with daemon mode - this should auto-spawn the daemon:

  $ dune exec ./foo.exe
  hello from exec

Verify the daemon is running:

  $ dune rpc ping
  Server appears to be responding normally

Clean up:

  $ dune shutdown

