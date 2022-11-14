Testing ambiguous paths and coqmod

  $ cat > dune-project << EOF
  > (lang dune 3.7)
  > (using coq 0.7)
  > EOF

  $ mkdir A

  $ cat > dune << EOF
  > (coq.theory
  >  (name T))
  > 
  > (include_subdirs qualified)
  > EOF

  $ cat > A/a.v << EOF
  > Inductive foo : Set := IComeFromA.
  > EOF

  $ mkdir B

  $ cat > B/a.v << EOF
  > Inductive foo : Set := IComeFromB.
  > EOF

  $ cat > A/test_local_a.v << EOF
  > Require a.
  > Print a.foo.
  > EOF

  $ dune build A/test_local_a.vo
  Actual module: [ "T"; "A"; "test_local_a" ]
  Found modules:
  [ "T"; "B"; "a" ]
  [ "T"; "A"; "a" ]
  [ "T"; "A"; "a" ]
  chosen m: [ "T"; "A"; "a" ]
  after suff: [ "T"; "A" ]
  [ "T"; "B"; "a" ]
  chosen m: [ "T"; "B"; "a" ]
  after suff: [ "T"; "B" ]
  Inductive foo : Set :=  IComeFromB : a.foo.

  $ cat > file.v << EOF
  > Require a.
  > Print a.foo.
  > EOF

  $ dune build file.vo --always-show-command-line
  Actual module: [ "T"; "file" ]
  Found modules:
  [ "T"; "B"; "a" ]
  [ "T"; "A"; "a" ]
  [ "T"; "A"; "a" ]
  chosen m: [ "T"; "A"; "a" ]
  after suff: [ "T"; "A" ]
  [ "T"; "B"; "a" ]
  chosen m: [ "T"; "B"; "a" ]
  after suff: [ "T"; "B" ]
  (cd _build/default && /nix/store/sn2ahp5pbs1cklpajv7cdjnzfgdwwj05-coq-8.16.0/bin/coqc -q -w -deprecated-native-compiler-option -native-output-dir . -native-compiler on -nI /nix/store/sn2ahp5pbs1cklpajv7cdjnzfgdwwj05-coq-8.16.0/lib/ocaml/4.14.0/site-lib/coq-core/kernel -nI . -nI A -nI B -R . T file.v)
  Inductive foo : Set :=  IComeFromB : a.foo.

  $ dune clean

  $ dune build A/ B/
  Actual module: [ "T"; "A"; "test_local_a" ]
  Found modules:
  [ "T"; "B"; "a" ]
  [ "T"; "A"; "a" ]
  [ "T"; "A"; "a" ]
  chosen m: [ "T"; "A"; "a" ]
  after suff: [ "T"; "A" ]
  [ "T"; "B"; "a" ]
  chosen m: [ "T"; "B"; "a" ]
  after suff: [ "T"; "B" ]
  File "./A/test_local_a.v", line 1, characters 0-10:
  Error: Required library a matches several files in path (found
  $TESTCASE_ROOT/_build/default/A/a.vo and
  $TESTCASE_ROOT/_build/default/B/a.vo).
  
  [1]

  $ dune build file.vo --always-show-command-line
  Actual module: [ "T"; "file" ]
  Found modules:
  [ "T"; "B"; "a" ]
  [ "T"; "A"; "a" ]
  [ "T"; "A"; "a" ]
  chosen m: [ "T"; "A"; "a" ]
  after suff: [ "T"; "A" ]
  [ "T"; "B"; "a" ]
  chosen m: [ "T"; "B"; "a" ]
  after suff: [ "T"; "B" ]
  (cd _build/default && /nix/store/sn2ahp5pbs1cklpajv7cdjnzfgdwwj05-coq-8.16.0/bin/coqc -q -w -deprecated-native-compiler-option -native-output-dir . -native-compiler on -nI /nix/store/sn2ahp5pbs1cklpajv7cdjnzfgdwwj05-coq-8.16.0/lib/ocaml/4.14.0/site-lib/coq-core/kernel -nI . -nI A -nI B -R . T file.v)
  File "./file.v", line 1, characters 0-10:
  Error: Required library a matches several files in path (found
  $TESTCASE_ROOT/_build/default/A/a.vo and
  $TESTCASE_ROOT/_build/default/B/a.vo).
  
  [1]
