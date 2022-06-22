We test composing a project with an installed Coq theory. The installed theory
does *not* have to be a dune project.

We configure COQLIB to be the current directory. Coq will search for
user-contrib from here.
  $ export COQLIB=$PWD
  $ echo $COQLIB
  $TESTCASE_ROOT

Manually installing a theory
  $ coqc -boot -noinit -Q user-contrib/B B user-contrib/B/b.v
  $ ls user-contrib/B
  b.glob
  b.v
  b.vo
  b.vok
  b.vos

Next we go into our Dune project and build it.
  $ cd A
  $ dune build --root=.
  *** Warning: cannot open $TESTCASE_ROOT/theories
  *** Warning: cannot open $TESTCASE_ROOT/../coq-core/plugins
  Warning:
  Cannot open directory $TESTCASE_ROOT/../coq-core/plugins
  [cannot-open-dir,filesystem]
  Warning:
  Cannot open $TESTCASE_ROOT/theories
  [cannot-open-path,filesystem]
  Inductive hello : Set :=
      I : hello | am : hello | an : hello | install : hello | loc : hello.

  $ cat _build/log \
  > | tail -n 12 \
  > | sed 's/$ //' \
  > | sed 's/> //' \
  > | sed 's/(cd .*coqc/coqc/' \
  > | sed 's/(cd .*coqdep/coqdep/' \
  > | sed 's/-nI .*coq-core/coq-core/' \
  > | sed 's/-R .*coq/coq/'
  coqdep -Q $TESTCASE_ROOT/user-contrib/B B -R . A -dyndep opt a.v) _build/default/A.theory.d
  *** Warning: cannot open $TESTCASE_ROOT/theories
  *** Warning: cannot open $TESTCASE_ROOT/../coq-core/plugins
  coqc -noinit -w -deprecated-native-compiler-option -native-output-dir . -native-compiler on coq-core/kernel -nI . -Q $TESTCASE_ROOT/user-contrib/B B -R . A a.v)
  Warning:
  Cannot open directory $TESTCASE_ROOT/../coq-core/plugins
  [cannot-open-dir,filesystem]
  Warning:
  Cannot open $TESTCASE_ROOT/theories
  [cannot-open-path,filesystem]
  Inductive hello : Set :=
      I : hello | am : hello | an : hello | install : hello | loc : hello.
