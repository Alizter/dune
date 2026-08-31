The shared Opam package rule processes generated .install and .config files and
records their contents in the install cookie.

  $ unset DUNE_SOURCE_ROOT DUNE_SOURCEROOT DUNE_PROJECT_ROOT
  $ mkdir foo consumer
  $ cat >dune-project <<'EOF'
  > (lang dune 3.24)
  > (name test)
  > (using unreleased 0.1)
  > (package
  >  (name foo)
  >  (version 1.0)
  >  (dir foo))
  > (package
  >  (name consumer)
  >  (dir consumer)
  >  (depends foo))
  > EOF

  $ cat >foo/dune <<'EOF'
  > (opam
  >  (package foo)
  >  (build
  >   (progn
  >    (system "echo installed-from-file > payload")
  >    (system "echo 'share: [ \"payload\" {\"from-install-file.txt\"} ]' > foo.install")
  >    (system "printf 'opam-version: \"2.0\"\\nvariables { answer: \"from-config\" }\\n' > foo.config"))))
  > EOF

  $ cat >consumer/dune <<'EOF'
  > (opam
  >  (package consumer)
  >  (build
  >   (system "echo %{pkg:foo:answer} > answer.txt"))
  >  (install
  >   (run cp answer.txt %{share}/answer.txt)))
  > EOF

  $ dune build consumer/.opam/consumer/target
  $ cat _build/default/foo/.opam/foo/target/share/foo/from-install-file.txt
  installed-from-file
  $ cat _build/default/consumer/.opam/consumer/target/share/answer.txt
  from-config
  $ test -f _build/default/foo/.opam/foo/target/cookie
  $ test ! -e foo/foo.install
  $ test ! -e foo/foo.config
