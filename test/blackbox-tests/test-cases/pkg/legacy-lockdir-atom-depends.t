Legacy lock directories written before the conditional format use a bare atom
for `depends` entries. They must decode and behave as unconditional
dependencies.

  $ make_lockdir

  $ make_lockpkg dep <<EOF
  > (version 0.0.1)
  > (install
  >  (progn
  >   (run mkdir -p %{pkg-self:lib})
  >   (run sh -c "echo from-dep > %{pkg-self:lib}/marker")))
  > EOF

  $ make_lockpkg consumer <<EOF
  > (version 0.0.1)
  > (depends dep)
  > (build
  >  (progn
  >   (run mkdir -p %{prefix}/lib/consumer)
  >   (run sh -c "cat %{pkg:dep:lib}/marker > %{prefix}/lib/consumer/copied")))
  > EOF

The atom form of depends decodes and is treated as an unconditional
dependency: building the consumer also builds `dep`, whose installed file is
readable through %{pkg:dep:lib}.

  $ build_pkg consumer

  $ cat $pkg_root/$(dune pkg print-digest consumer)/target/lib/consumer/copied
  from-dep

The dependency package was built and its installed file exists:
  $ show_pkg dep
  
  /target
  /target/bin
  /target/cookie
  /target/doc
  /target/doc/dep
  /target/etc
  /target/etc/dep
  /target/lib
  /target/lib/dep
  /target/lib/dep/marker
  /target/lib/stublibs
  /target/lib/toplevel
  /target/man
  /target/sbin
  /target/share
  /target/share/dep
