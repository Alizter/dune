Testing that timeout errors don't include the command that caused the timeout.

This test demonstrates the current behavior where timeout error messages
don't include information about which specific command caused the timeout.

  $ cat > dune-project <<EOF
  > (lang dune 3.20)
  > EOF

  $ cat > dune <<EOF
  > (cram
  >  (timeout 0.1))
  > EOF

Create a cram test with multiple commands, where the second one will timeout:

  $ cat > test.t <<EOF
  >   $ echo "This command runs fine"
  >   $ echo "This is the problematic command" && sleep 2
  > EOF

Run the test and verify that the timeout error shows which command timed out:

  $ dune test test.t
  File "test.t", line 1, characters 0-0:
  Error: Files _build/default/test.t and _build/default/test.t.corrected
  differ.
  File "test.t", line 2, characters 2-53:
  2 |   $ echo "This is the problematic command" && sleep 2
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: Cram test timed out
  A time limit of 0.10s has been set in dune:2
  [1]

Try to promote the partial output from commands that ran before the timeout:
  $ dune promote
  Promoting _build/default/test.t.corrected to test.t.

Check if the first command's output was captured before the timeout:
  $ cat test.t
    $ echo "This command runs fine"
    This command runs fine
    $ echo "This is the problematic command" && sleep 2
