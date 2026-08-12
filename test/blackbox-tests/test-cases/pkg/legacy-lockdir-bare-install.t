Legacy lock directories written before the conditional format carry bare
`install` commands (not wrapped in a `(choice ...)`). They must be carried
through and executed, not silently dropped.

  $ make_lockdir

  $ make_lockpkg test <<EOF
  > (version 0.0.1)
  > (install
  >  (progn
  >   (run mkdir -p %{pkg-self:bin})
  >   (run sh -c "echo hello > %{pkg-self:bin}/hello")))
  > EOF

  $ build_pkg test

The bare install command was executed: the installed file exists in the
package target.
  $ cat $pkg_root/$(dune pkg print-digest test)/target/bin/hello
  hello

The installed file is recorded in the package cookie.
  $ show_pkg_cookie test
  { files =
      [ (BIN,
         [ In_build_dir
             "_private/default/.pkg/test.0.0.1-$DIGEST/target/bin/hello"
         ])
      ]
  ; variables = []
  }
