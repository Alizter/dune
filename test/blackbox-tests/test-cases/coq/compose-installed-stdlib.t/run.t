Testing the composition of the installed stdlib

  $ cat > dune << EOF
  > (coq.theory
  >  (name test)
  >  (theories Coq))
  > EOF

  $ dune build test.vo --display=short --always-show-command-line
        coqdep .test.theory.d
  File "dune", line 1, characters 0-41:
  1 | (coq.theory
  2 |  (name test)
  3 |  (theories Coq))
          coqc Ntest_test.{cmi,cmxs},test.{glob,vo} (exit 1)
  (cd _build/default && /nix/store/x4k9020dvlpw1g41rsrqmsd0isxd248q-coq-8.16.1/bin/coqc -q -w -deprecated-native-compiler-option -native-output-dir . -native-compiler on -nI /nix/store/x4k9020dvlpw1g41rsrqmsd0isxd248q-coq-8.16.1/lib/ocaml/4.14.0/site-lib/coq-core/kernel -nI . -boot -R /nix/store/x4k9020dvlpw1g41rsrqmsd0isxd248q-coq-8.16.1/lib/coq/theories Coq -R . test test.v)
  Error: Can't find file ltac_plugin.cmxs on loadpath.
  
  [1]


  $ coqc --config
  COQLIB=/nix/store/x4k9020dvlpw1g41rsrqmsd0isxd248q-coq-8.16.1/lib/coq/
  COQCORELIB=/nix/store/x4k9020dvlpw1g41rsrqmsd0isxd248q-coq-8.16.1/lib/coq/../coq-core/
  DOCDIR=/nix/store/x4k9020dvlpw1g41rsrqmsd0isxd248q-coq-8.16.1/share/doc/
  OCAMLFIND=/nix/store/xa4p81c1x6xwiyvliq7323h68vx6ygh9-ocaml4.14.0-findlib-1.9.6/bin/ocamlfind
  CAMLFLAGS=-thread -rectypes -w -a+1..3-4+5..8-9+10..26-27+28..40-41-42+43-44-45+46..47-48+49..57-58+59..66-67-68+69-70   -safe-string -strict-sequence
  WARN=-warn-error +a-3
  HASNATDYNLINK=true
  COQ_SRC_SUBDIRS=boot config lib clib kernel library engine pretyping interp gramlib parsing proofs tactics toplevel printing ide stm vernac plugins/btauto plugins/cc plugins/derive plugins/extraction plugins/firstorder plugins/funind plugins/ltac plugins/ltac2 plugins/micromega plugins/nsatz plugins/ring plugins/rtauto plugins/ssr plugins/ssrmatching plugins/syntax
  COQ_NATIVE_COMPILER_DEFAULT=ondemand

$ cat _build/log \
> | tail -n 2 \
> | sed 's/$ //' \
> | sed 's/(cd .*coqc/coqc/' \
> | sed 's/(cd .*coqdep/coqdep/' \
> | sed 's/-nI .*coq-core/coq-core/' \
> | sed 's/-R .*coq/coq/'
> 

  $ ls _build/default
  test.v
