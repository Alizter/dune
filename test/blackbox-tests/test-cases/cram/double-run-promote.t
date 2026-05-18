This test demonstrates that cram tests are not re-run after promotion
(because the script-generation step's output is content-stable), and
that passing --force does re-run them.

  $ cat >dune-project<<EOF
  > (lang dune 3.12)
  > EOF

  $ cat >foo.t <<EOF
  >   $ echo run >> $PWD/side-effect
  >   $ echo bazy
  > EOF

  $ dune runtest foo.t
  File "foo.t", line 1, characters 0-0:
  --- foo.t
  +++ foo.t.corrected
  @@ -1,2 +1,3 @@
     $ echo run >> $TESTCASE_ROOT/side-effect
     $ echo bazy
  +  bazy
  [1]
  $ cat side-effect
  run
  $ dune promote
  Promoting _build/default/foo.t.corrected to foo.t.
  $ dune runtest foo.t

side-effect should only contain a single "run":

  $ cat side-effect
  run

Passing --force re-runs the cram test:

  $ dune runtest foo.t --force

There should be two "run"s here:
  $ cat side-effect
  run
  run

