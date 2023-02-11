We test composing a project with an installed Coq theory. The installed theory
does *not* have to be a dune project.
  $ function realpath { echo $(cd $(dirname $1); pwd)/$(basename $1); }

  $ export COQLIB=$(realpath .)

  $ echo $COQLIB
  $TESTCASE_ROOT/.

  $ coqc -boot -noinit -Q user-contrib/B B user-contrib/B/b.v

  $ ls user-contrib/B
  b.glob
  b.v
  b.vo
  b.vok
  b.vos

  $ ls
  A
  user-contrib

  $ cd A
  $ dune build --root=.
  *** Warning: cannot open $TESTCASE_ROOT/./theories
  *** Warning: cannot open $TESTCASE_ROOT/./../coq-core/plugins
  Warning:
  Cannot open directory $TESTCASE_ROOT/./../coq-core/plugins
  [cannot-open-dir,filesystem]
  Warning:
  Cannot open $TESTCASE_ROOT/./theories
  [cannot-open-path,filesystem]
  Inductive hello : Set :=
      I : hello | am : hello | an : hello | install : hello | loc : hello.

$ cat _build/log | sed -n 's/^\$ //p' | tail -n 2
