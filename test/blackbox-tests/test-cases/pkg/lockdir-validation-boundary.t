Lock directory checks against the workspace run when rules are generated,
not when the lock directory is read. Check that consumers reached before
ordinary directory rules still get a lock directory diagnostic.

Only the first line of each diagnostic is shown.

  $ first_error() { grep -m1 -E '^(Error|Internal error)' | cut -c1-60 | sed 's/ *$//'; }

A workspace package that is also an opaque package in the lock directory:

  $ make_lockdir
  $ make_lockpkg foo <<EOF
  > (version 0.0.1)
  > (build (run echo building foo))
  > EOF
  $ cat > dune-project <<EOF
  > (lang dune 3.20)
  > (package (name foo) (allow_empty))
  > EOF
  $ cat > dune <<EOF
  > (rule (target x) (action (with-stdout-to x (echo x))))
  > EOF

Requesting the opaque package's install target directly, before anything
else has been built:

  $ dune build _build/default/.pkg/foo/_install 2>&1 | first_error
  Error: A package named "foo" is defined locally but is also
  [1]

Building an unrelated workspace target:

  $ rm -rf _build
  $ dune build ./x 2>&1 | first_error
  Error: A package named "foo" is defined locally but is also
  [1]

A locked package depending on a package that is neither locked nor in the
workspace:

  $ cat > dune-project <<EOF
  > (lang dune 3.20)
  > EOF
  $ make_lockpkg foo <<EOF
  > (version 0.0.1)
  > (depends missing)
  > (build (run echo building foo))
  > EOF

Through context creation only:

  $ rm -rf _build
  $ dune build ./x 2>&1 | first_error
  Error: At least one package dependency is itself not present
  [1]

Through the locked package's install target:

  $ rm -rf _build
  $ dune build _build/default/.pkg/foo/_install 2>&1 | first_error
  Error: At least one package dependency is itself not present
  [1]

Through a workspace consumer that depends on it:

  $ cat > dune <<EOF
  > (rule
  >  (target y)
  >  (deps (package foo))
  >  (action (with-stdout-to y (echo y))))
  > EOF
  $ rm -rf _build
  $ dune build ./y 2>&1 | first_error
  Error: At least one package dependency is itself not present
  [1]

The same two problems with the lock directory's compiler package, which is
resolved when the build context is created:

  $ rm -rf _build
  $ cat >> ${source_lock_dir}/lock.dune <<EOF
  > (ocaml mycaml)
  > EOF
  $ make_lockpkg mycaml <<EOF
  > (version 0.0.1)
  > (depends missing)
  > (build (run echo building mycaml))
  > EOF
  $ rm ${source_lock_dir}/foo.pkg
  $ cat > dune <<EOF
  > (rule (alias foo) (action (echo foo)))
  > EOF
  $ dune build @foo 2>&1 | first_error
  Error: At least one package dependency is itself not present
  [1]

  $ make_lockpkg mycaml <<EOF
  > (version 0.0.1)
  > (build (run echo building mycaml))
  > EOF
  $ cat > dune-project <<EOF
  > (lang dune 3.20)
  > (package (name mycaml) (allow_empty))
  > EOF
  $ rm -rf _build
  $ dune build @foo 2>&1 | first_error
  Error: A package named "mycaml" is defined locally but is al
  [1]
