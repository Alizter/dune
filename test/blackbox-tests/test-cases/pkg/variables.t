Test that we can set variables

  $ make_lockdir
  $ make_lockpkg test <<EOF
  > (version 0.0.1)
  > (build
  >  (system "\| cat >test.config <<EOF
  >          "\| opam-version: "2.0"
  >          "\| variables {
  >          "\|   abool: true
  >          "\|   astring: "foobar"
  >          "\|   somestrings: ["foo" "bar"]
  >          "\|   version: "1.2.3"
  >          "\| }
  >          "\| EOF
  >  ))
  > EOF

  $ make_lockpkg usetest <<EOF
  > (version 0.0.1)
  > (depends test)
  > (build
  >  (progn
  >   (system "\| echo abool: %{pkg:test:abool}
  >           "\| echo astring: %{pkg:test:astring}
  >           "\| echo somestrings: %{pkg:test:somestrings}
  >           "\| echo share path: %{pkg:test:share}
  >           "\| echo version: %{pkg:test:version}
  >   )
  >   (run mkdir -p %{prefix})))
  > EOF

  $ build_pkg usetest 2>&1 | censor
  abool: true
  astring: foobar
  somestrings: foo bar
  share path: ../../../../test/.opam/test/target/share/test
  version: 1.2.3

  $ show_pkg_cookie test
  { files = []
  ; variables =
      [ ("abool", Bool true)
      ; ("astring", String "foobar")
      ; ("somestrings", Strings [ "foo"; "bar" ])
      ; ("version", String "1.2.3")
      ]
  }

Now we demonstrate we get a proper error from invalid .config files:

  $ make_lockpkg test <<EOF
  > (version 0.0.1)
  > (build
  >  (system "\| cat >test.config <<EOF
  >          "\| this is dummy text
  >          "\| EOF
  >  ))
  > EOF

  $ build_pkg test 2>&1 | dune_cmd subst 'File .*:' 'File $REDACTED:' | censor
  Error:
  File $REDACTED:
  1 | this is dummy text
           ^^
  Error parsing test.config
  Reason: Parse error
  -> required by _build/_default+lockfile/pkg/test/.opam/test/target
  [1]

The lock's development flag is independent of its version. Both native and
opaque dependencies must retain it when materialized as package providers.

  $ mkdir dev-variables
  $ cd dev-variables
  $ cat > dune-project <<'EOF'
  > (lang dune 3.24)
  > (using unreleased 0.1)
  > (package
  >  (name consumer)
  >  (allow_empty)
  >  (depends native dev-pkg release-pkg))
  > EOF
  $ cat > dune <<'EOF'
  > (dirs :standard \ native-source)
  > (opam
  >  (package consumer)
  >  (build
  >   (run echo workspace:
  >    %{pkg:native:dev} %{pkg:dev-pkg:dev} %{pkg:release-pkg:dev})))
  > EOF
  $ mkdir native-source
  $ cat > native-source/dune-project <<'EOF'
  > (lang dune 3.24)
  > (package (name native) (allow_empty))
  > EOF
  $ echo '(rule (alias all) (action (echo native)))' > native-source/dune
  $ make_lockdir
  $ make_lockpkg native <<EOF
  > (version 1.0)
  > (dev)
  > (source (copy $PWD/native-source))
  > EOF
  $ make_lockpkg dev-pkg <<'EOF'
  > (version 1.0)
  > (dev)
  > (build
  >  (progn
  >   (run echo self: %{pkg-self:dev})
  >   (when %{pkg-self:dev} (run echo development-action))))
  > EOF
  $ make_lockpkg release-pkg <<'EOF'
  > (version 1.0)
  > EOF
  $ make_lockpkg locked-consumer <<'EOF'
  > (version 1.0)
  > (depends native dev-pkg release-pkg)
  > (build
  >  (run echo locked:
  >   %{pkg:native:dev} %{pkg:dev-pkg:dev} %{pkg:release-pkg:dev}))
  > EOF

The development action runs and the first two dependency flags are true,
regardless of whether the consumer is locked or workspace-owned.

  $ build_pkg locked-consumer
  self: true
  development-action
  locked: true true false
  $ dune build .opam/consumer/target
  workspace: true true false

Changing only the development flag at the same package-name root must also be
observed by the next build.

  $ sed -i '/^(dev)$/d' dune.lock/native.pkg dune.lock/dev-pkg.pkg
  $ build_pkg locked-consumer
  self: false
  locked: false false false
  $ dune build .opam/consumer/target
  workspace: false false false
