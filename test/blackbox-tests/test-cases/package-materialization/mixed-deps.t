Test that package deps and file deps work together in the same (deps ...).

  $ cat >dune-project <<EOF
  > (lang dune 3.24)
  > (package (name foo))
  > EOF

  $ mkdir src

  $ cat >src/dune <<EOF
  > (library (public_name foo))
  > EOF

  $ cat >src/mylib.ml <<EOF
  > let x = 1
  > EOF

  $ cat >dune <<'EOF'
  > (rule
  >  (deps (package foo) (file src/mylib.ml))
  >  (action (with-stdout-to out (echo "ok"))))
  > EOF

  $ dune build out

The file dep appears alongside the layout deps:

  $ dune rules --format=json _build/default/out | jq 'include "dune"; .[] | ruleDepFilePaths' | censor | sort
  "_build/default/.install-layout/$DIGEST/lib/foo/META"
  "_build/default/.install-layout/$DIGEST/lib/foo/dune-package"
  "_build/default/.install-layout/$DIGEST/lib/foo/foo.a"
  "_build/default/.install-layout/$DIGEST/lib/foo/foo.cma"
  "_build/default/.install-layout/$DIGEST/lib/foo/foo.cmi"
  "_build/default/.install-layout/$DIGEST/lib/foo/foo.cmt"
  "_build/default/.install-layout/$DIGEST/lib/foo/foo.cmx"
  "_build/default/.install-layout/$DIGEST/lib/foo/foo.cmxa"
  "_build/default/.install-layout/$DIGEST/lib/foo/foo.cmxs"
  "_build/default/.install-layout/$DIGEST/lib/foo/foo.ml"
  "_build/default/.install-layout/$DIGEST/lib/foo/foo__Mylib.cmi"
  "_build/default/.install-layout/$DIGEST/lib/foo/foo__Mylib.cmt"
  "_build/default/.install-layout/$DIGEST/lib/foo/foo__Mylib.cmx"
  "_build/default/.install-layout/$DIGEST/lib/foo/mylib.ml"
  "_build/default/src/mylib.ml"
