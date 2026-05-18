The --force flag is documented as "Force actions associated to aliases
to be re-executed even if their dependencies haven't changed". For cram
tests this is supposed to re-execute the cram script. Since the cram
rule split in #11994 (3.21) the cram run is a normal file-target rule,
so --force does not re-run it.

  $ make_dune_project 3.20

A cram test whose only effect is appending a line to a file in the
outer test's working directory. The command itself produces no stdout,
so the inner cram diff is empty and runtest succeeds silently.

  $ cat >foo.t <<EOF
  >   $ echo ran >> $PWD/runs
  > EOF

  $ dune runtest foo.t

After the initial run, the cram script has executed once:

  $ wc -l <runs
  1

A bare second runtest should NOT re-run (output is cached):

  $ dune runtest foo.t
  $ wc -l <runs
  1

Re-running with --force should re-execute the cram script:

  $ dune runtest foo.t --force
  $ wc -l <runs
  2

Two more --force invocations should each add one more line:

  $ dune runtest foo.t --force
  $ dune runtest foo.t --force
  $ wc -l <runs
  4
