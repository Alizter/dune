Test that (deps (package foo)) resolves to precise file-level deps in
a materialized install layout, not just an alias.

  $ cat >dune-project <<EOF
  > (lang dune 3.24)
  > (package (name foo))
  > (package (name bar))
  > EOF

  $ mkdir src src2

  $ cat >src/dune <<EOF
  > (library (public_name foo))
  > EOF

  $ cat >src/mylib.ml <<EOF
  > let x = 1
  > EOF

  $ cat >src2/dune <<EOF
  > (library (public_name bar))
  > EOF

  $ cat >src2/mylib2.ml <<EOF
  > let y = 2
  > EOF

  $ cat >dune <<'EOF'
  > (rule
  >  (deps (package foo))
  >  (action (with-stdout-to out1 (echo "ok"))))
  > (rule
  >  (deps (package foo) (package bar))
  >  (action (with-stdout-to out2 (echo "ok"))))
  > (rule
  >  (deps (package bar) (package foo))
  >  (action (with-stdout-to out_rev (echo "ok"))))
  > (rule
  >  (deps (package bar))
  >  (action (with-stdout-to out3 (echo "ok"))))
  > EOF

  $ dune build out1 out2 out_rev out3

Single package dep produces file-level deps under a layout directory:

  $ dune rules --format=json _build/default/out1 | jq 'include "dune"; .[] | ruleDepFilePaths' | censor | sort
  "_build/default/.install-layout/$DIGEST/lib/bar/META"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar.a"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar.cma"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar.cmi"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar.cmt"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar.cmx"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar.cmxa"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar.cmxs"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar.ml"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar__Mylib2.cmi"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar__Mylib2.cmt"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar__Mylib2.cmx"
  "_build/default/.install-layout/$DIGEST/lib/bar/dune-package"
  "_build/default/.install-layout/$DIGEST/lib/bar/mylib2.ml"
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

Two packages coalesce into a single layout directory (both under same digest):

  $ dune rules --format=json _build/default/out2 | jq 'include "dune"; .[] | ruleDepFilePaths' | censor | sort
  "_build/default/.install-layout/$DIGEST/lib/bar/META"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar.a"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar.cma"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar.cmi"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar.cmt"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar.cmx"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar.cmxa"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar.cmxs"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar.ml"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar__Mylib2.cmi"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar__Mylib2.cmt"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar__Mylib2.cmx"
  "_build/default/.install-layout/$DIGEST/lib/bar/dune-package"
  "_build/default/.install-layout/$DIGEST/lib/bar/mylib2.ml"
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

Order of package deps does not matter — same deps regardless of order:

  $ dune rules --format=json _build/default/out2 | jq 'include "dune"; .[] | ruleDepFilePaths' | sort > deps_fwd.txt
  $ dune rules --format=json _build/default/out_rev | jq 'include "dune"; .[] | ruleDepFilePaths' | sort > deps_rev.txt
  $ diff deps_fwd.txt deps_rev.txt

Different package set produces a different layout directory:

  $ dune rules --format=json _build/default/out3 | jq 'include "dune"; .[] | ruleDepFilePaths' | censor | sort
  "_build/default/.install-layout/$DIGEST/lib/bar/META"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar.a"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar.cma"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar.cmi"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar.cmt"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar.cmx"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar.cmxa"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar.cmxs"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar.ml"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar__Mylib2.cmi"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar__Mylib2.cmt"
  "_build/default/.install-layout/$DIGEST/lib/bar/bar__Mylib2.cmx"
  "_build/default/.install-layout/$DIGEST/lib/bar/dune-package"
  "_build/default/.install-layout/$DIGEST/lib/bar/mylib2.ml"
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
