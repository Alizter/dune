Packages can export environment variables

  $ make_lockdir
  $ make_lockpkg test <<EOF
  > (version 0.0.1)
  > (exported_env
  >  (= FOO bar)
  >  (= BAR xxx)
  >  (+= BAR yyy)
  >  (:= BAR zzz))
  > EOF

  $ make_lockpkg usetest <<'EOF'
  > (depends test)
  > (version 1.2.3)
  > (build
  >  (progn
  >   (system "\| echo FOO=$FOO
  >           "\| echo BAR=$BAR
  >           "\| echo OPAM_PACKAGE_NAME=$OPAM_PACKAGE_NAME
  >           "\| echo OPAM_PACKAGE_VERSION=$OPAM_PACKAGE_VERSION
  >           "\| echo OPAMSWITCH=$OPAMSWITCH
  >   )
  >   (run mkdir -p %{prefix})))
  > EOF

  $ build_pkg usetest
  FOO=bar
  BAR=zzz:yyy:xxx
  OPAM_PACKAGE_NAME=usetest
  OPAM_PACKAGE_VERSION=1.2.3
  OPAMSWITCH=dune

Native packages must contribute their lock-declared exports to the same
package-set environment as opaque packages. Both locked and workspace Opam
consumers must see these exports.

  $ mkdir native-exports
  $ cd native-exports
  $ cat >dune-project <<'EOF'
  > (lang dune 3.24)
  > (using unreleased 0.1)
  > (package
  >  (name workspace-consumer)
  >  (allow_empty)
  >  (depends native))
  > EOF
  $ cat >dune <<'EOF'
  > (dirs :standard \ native-source)
  > (opam
  >  (package workspace-consumer)
  >  (build (system "echo workspace=$NATIVE_EXPORT")))
  > EOF
  $ mkdir native-source
  $ cat >native-source/dune-project <<'EOF'
  > (lang dune 3.24)
  > (package (name native) (allow_empty))
  > EOF
  $ echo '(rule (alias all) (action (echo native-built)))' >native-source/dune
  $ make_lockdir
  $ make_lockpkg native <<EOF
  > (version 1.0)
  > (source (copy $PWD/native-source))
  > (exported_env (= NATIVE_EXPORT present))
  > EOF
  $ make_lockpkg locked-consumer <<'EOF'
  > (version 1.0)
  > (depends native)
  > (build (system "echo locked=$NATIVE_EXPORT"))
  > EOF

  $ build_pkg locked-consumer
  locked=present
  $ dune build .opam/workspace-consumer/target
  workspace=present
