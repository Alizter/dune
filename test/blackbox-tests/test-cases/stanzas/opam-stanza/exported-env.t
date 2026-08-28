Exported environments use the same update semantics as lock-directory packages
and are visible to both Opam-built and native dependants.

  $ unset DUNE_SOURCE_ROOT DUNE_SOURCEROOT DUNE_PROJECT_ROOT
  $ mkdir -p mock-opam-repository/packages base consumer native
  $ cat >mock-opam-repository/repo <<'EOF'
  > opam-version: "2.0"
  > EOF
  $ cat >dune-workspace <<EOF
  > (lang dune 3.22)
  > (pkg disabled)
  > (lock_dir
  >  (repositories mock))
  > (repository
  >  (name mock)
  >  (url "file://$PWD/mock-opam-repository"))
  > EOF
  $ cat >dune-project <<'EOF'
  > (lang dune 3.22)
  > (name test)
  > (using unreleased 0.1)
  > (package
  >  (name base)
  >  (version 1.0)
  >  (dir base))
  > (package
  >  (name consumer)
  >  (version 2.0)
  >  (dir consumer)
  >  (depends base))
  > (package
  >  (name native)
  >  (dir native)
  >  (depends base)
  >  (allow_empty))
  > EOF

  $ cat >base/dune <<'EOF'
  > (opam
  >  (package base)
  >  (exported_env
  >   (= FOO bar)
  >   (= BAR xxx)
  >   (+= BAR yyy)
  >   (:= BAR zzz)
  >   (+= PLUS_PREPEND p)
  >   (:= COLON_PREPEND p)
  >   (=+ PLUS_APPEND a)
  >   (=: COLON_APPEND a)))
  > EOF

  $ cat >consumer/dune <<'EOF'
  > (opam
  >  (package consumer)
  >  (depends base)
  >  (build
  >   (progn
  >    (system "echo FOO=$FOO > env.txt")
  >    (system "echo BAR=$BAR >> env.txt")
  >    (system "echo PLUS_PREPEND=$PLUS_PREPEND >> env.txt")
  >    (system "echo COLON_PREPEND=$COLON_PREPEND >> env.txt")
  >    (system "echo PLUS_APPEND=$PLUS_APPEND >> env.txt")
  >    (system "echo COLON_APPEND=$COLON_APPEND >> env.txt")
  >    (system "echo OPAM_PACKAGE_NAME=$OPAM_PACKAGE_NAME >> env.txt")
  >    (system "echo OPAM_PACKAGE_VERSION=$OPAM_PACKAGE_VERSION >> env.txt")))
  >  (install
  >   (run cp env.txt %{share}/env.txt)))
  > EOF

  $ cat >native/dune <<'EOF'
  > (rule
  >  (target env.txt)
  >  (action
  >   (with-stdout-to %{target}
  >    (run sh -c "echo FOO=$FOO"))))
  > EOF

  $ dune build consumer/.opam/consumer/target native/env.txt
  $ cat _build/default/consumer/.opam/consumer/target/share/env.txt
  FOO=bar
  BAR=zzz:yyy:xxx
  PLUS_PREPEND=p
  COLON_PREPEND=p:
  PLUS_APPEND=a
  COLON_APPEND=:a
  OPAM_PACKAGE_NAME=consumer
  OPAM_PACKAGE_VERSION=2.0
  $ cat _build/default/native/env.txt
  FOO=bar
