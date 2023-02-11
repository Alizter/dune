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

  $ cat _build/log \
  > | tail -n 2 \
  > | sed 's/$ //' \
  > | sed 's/(cd .*coqc/coqc/' \
  > | sed 's/(cd .*coqdep/coqdep/' \
  > | sed 's/-nI .*coq-core/coq-core/' \
  > | sed 's/-R .*coq/coq/' \
  coqdep coq/theories Coq -R . test -dyndep opt test.v) > _build/default/test.v.d
  coqc -q -w -deprecated-native-compiler-option -w -native-compiler-disabled -native-compiler ondemand coq/theories Coq -R . test test.v)

  $ ls _build/default
  test.glob
  test.v
  test.v.d
  test.vo
  test.vok
  test.vos
