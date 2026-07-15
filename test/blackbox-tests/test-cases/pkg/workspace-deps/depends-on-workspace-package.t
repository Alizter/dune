A workspace package depends on a lock-dir package which depends on another
workspace package:

app (workspace) -> mylock (lock dir) -> myws (workspace)

  $ make_dune_project 3.24
  $ cat >> dune-project <<EOF
  > (package (name myws))
  > (package
  >  (name app)
  >  (allow_empty)
  >  (depends mylock))
  > EOF

  $ mkdir src
  $ cat > src/dune <<EOF
  > (library (public_name myws))
  > EOF
  $ cat > src/myws.ml <<EOF
  > let x = 1
  > EOF

The lock dir contains one package "mylock" that declares "myws" as a
dependency:

  $ make_lockdir
  $ make_lockpkg mylock <<EOF
  > (version 0.0.1)
  > (depends myws)
  > (build (run echo "building mylock"))
  > EOF

A rule depends on the lock-dir package:

  $ cat > dune <<EOF
  > (rule
  >  (alias check)
  >  (deps (package mylock))
  >  (action (with-stdout-to out (echo "done"))))
  > EOF

The build accepts the complete in-and-out graph and runs [mylock]'s build
action. The workspace package's artifacts are exercised by the focused tests
in [lockdir-workspace-deps].

  $ dune build @check 2>&1
  building mylock
