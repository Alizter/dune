Test that cram tests with timeouts can still partially promote output from
commands that executed successfully before the timeout.

  $ cat > dune-project <<EOF
  > (lang dune 3.21)
  > EOF

Create a test with some successful commands, then a command that will timeout:

  $ cat > test.t <<EOF
  >   $ echo "First command"
  >   $ echo "Second command"
  >   $ sleep 10
  > EOF

  $ cat > dune <<EOF
  > (cram
  >  (timeout 0.5))
  > EOF

The test should fail with timeout error, but the corrected file should still be
created with partial output:

  $ dune runtest
  File "test.t", line 1, characters 0-0:
  Error: Files _build/default/test.t and _build/default/test.t.corrected
  differ.
  File "test.t", line 3, characters 2-12:
  3 |   $ sleep 10
        ^^^^^^^^^^
  Error: Cram test timed out
  A time limit of 0.50s has been set in dune:2
  [1]

Now promote the partial output:

  $ dune promote
  Promoting _build/default/test.t.corrected to test.t.

After promotion, the test file should have the partial output:

  $ cat test.t
    $ echo "First command"
    First command
    $ echo "Second command"
    Second command
    $ sleep 10
