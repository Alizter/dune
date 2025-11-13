Syntax error inside a cram command
  $ mkdir foo && cd foo
  $ cat >dune-project <<EOF
  > (lang dune 3.0)
  > EOF

  $ cat >t1.t <<EOF
  >   $ if then fi
  > EOF

  $ dune runtest --auto-promote
  File "t1.t", line 1, characters 0-0:
  Error: Files _build/default/t1.t and _build/default/t1.t.corrected differ.
  File "t1.t", line 1, characters 2-14:
  1 |   $ if then fi
        ^^^^^^^^^^^^
  Error: Command exited the shell. Subsequent commands in this test are
  unreachable.
  Promoting _build/default/t1.t.corrected to t1.t.
  [1]

  $ cat t1.t
    $ if then fi
    ***** UNREACHABLE *****

  $ cat >t1.t <<EOF
  >   $ exit 1
  >   $ echo foobar
  > EOF
  $ dune runtest --auto-promote
  File "t1.t", line 1, characters 0-0:
  Error: Files _build/default/t1.t and _build/default/t1.t.corrected differ.
  File "t1.t", line 1, characters 2-10:
  1 |   $ exit 1
        ^^^^^^^^
  Error: Command exited the shell. Subsequent commands in this test are
  unreachable.
  Promoting _build/default/t1.t.corrected to t1.t.
  [1]

  $ cat t1.t
    $ exit 1
    ***** UNREACHABLE *****
    $ echo foobar
