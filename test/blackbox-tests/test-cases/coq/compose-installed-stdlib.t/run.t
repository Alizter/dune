Testing the composition of the installed stdlib

  $ cat > dune << EOF
  > (coq.theory
  >  (name test)
  >  (theories Coq))
  > EOF

  $ dune build test.vo

  $ cat _build/log \
  > | tail -n 2 \
  > | sed 's/$ //' \
  > | sed 's/(cd .*coqc/coqc/' \
  > | sed 's/(cd .*coqdep/coqdep/' \
  > | sed 's/-nI .*coq-core/coq-core/' \
  > | sed 's/-R .*coq/coq/' \
  coqdep coq/theories Coq -R . test -dyndep opt test.v) > _build/default/test.theory.d
  coqc -q -w -deprecated-native-compiler-option -native-output-dir . -native-compiler on coq-core/kernel -nI . coq/theories Coq -R . test test.v)

  $ ls _build/default
  Ntest_test.cmi
  Ntest_test.cmx
  Ntest_test.cmxs
  Ntest_test.o
  test.glob
  test.theory.d
  test.v
  test.v.d
  test.vo
  test.vok
  test.vos
