Test that daemon mode works with runtest command.

Create a simple project with daemon enabled in the workspace:

  $ cat > dune-workspace <<EOF
  > (lang dune 3.21)
  > (daemon (enabled true))
  > EOF

  $ cat > dune-project <<EOF
  > (lang dune 3.21)
  > EOF

  $ cat > dune <<EOF
  > (test (name foo))
  > EOF

  $ cat > foo.ml <<EOF
  > let () = print_endline "test passed"
  > EOF

Run test with daemon mode - this should auto-spawn the daemon:

  $ dune runtest
  Success

Now introduce a failing test:

  $ cat > foo.ml <<EOF
  > let () = failwith "test failed"
  > EOF

  $ dune runtest
  File "dune", line 1, characters 12-15:
  1 | (test (name foo))
                  ^^^
  Fatal error: exception Failure("test failed")
  Error: Build failed with 1 error.
  [1]

Verify the daemon is running:

  $ dune rpc ping
  Server appears to be responding normally

Clean up:

  $ dune shutdown
