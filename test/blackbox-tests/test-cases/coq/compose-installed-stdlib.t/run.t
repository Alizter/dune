Testing the composition of the installed stdlib

TODO test needs version bump
  $ cat > dune-project << EOF
  > (lang dune 3.7)
  > (using coq 0.7)
  > EOF

  $ cat > dune << EOF
  > (coq.theory
  >  (name test)
  >  (mode vo)
  >  (theories Coq))
  > EOF

  $ cat > test.v << EOF
  > From Coq Require Import List.
  > EOF

  $ dune build test.vo
  File "dune", line 1, characters 0-52:
  1 | (coq.theory
  2 |  (name test)
  3 |  (mode vo)
  4 |  (theories Coq))
  Error: Can't find file ltac_plugin.cmxs on loadpath.
  
  [1]

  $ cat _build/log | sed -n 's/^\$ //p' | tail -n 2
  (cd _build/default && /nix/store/x4k9020dvlpw1g41rsrqmsd0isxd248q-coq-8.16.1/bin/coqdep -boot -R /nix/store/x4k9020dvlpw1g41rsrqmsd0isxd248q-coq-8.16.1/lib/coq/theories Coq -R . test -dyndep opt test.v) > _build/default/test.v.d
  (cd _build/default && /nix/store/x4k9020dvlpw1g41rsrqmsd0isxd248q-coq-8.16.1/bin/coqc -q -w -deprecated-native-compiler-option -w -native-compiler-disabled -native-compiler ondemand -boot -R /nix/store/x4k9020dvlpw1g41rsrqmsd0isxd248q-coq-8.16.1/lib/coq/theories Coq -R . test test.v)

  $ ls _build/default
  test.v
  test.v.d
