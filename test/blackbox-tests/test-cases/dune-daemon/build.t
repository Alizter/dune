Test that daemon mode automatically spawns a daemon and forwards build requests.

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
  > let () = print_endline "hello"
  > EOF

Build with daemon mode - this should auto-spawn the daemon:

  $ dune build
  Success

Verify the daemon is running by pinging it:

  $ dune rpc ping
  Server appears to be responding normally

Run another build - should reuse the running daemon:

  $ cat > foo.ml <<EOF
  > #asdf
  > EOF

  $ dune build
  File "$TESTCASE_ROOT/foo.ml", line 1, characters 0-1:
  1 | #asdf
      ^
  Syntax error
  Error: Build failed with 1 error.
  [1]

Clean up by shutting down the daemon:

  $ dune shutdown
