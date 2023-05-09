Testing the interaction of --no-build and watch mode. We are looking to make
sure that dune coq top --no-build does not attempt to grab the build lock.

  $ . ./helpers.sh

  $ start_dune

  $ cat > a.v
  $ cat > b.v << EOF
  > Require a.
  > EOF

  $ dune coq top --no-build b.v --toplevel echo |& ../../scrub_coq_args.sh | sed 's/pid: [0-9]*/pid: $pid\)/'
  Error: A running dune (pid: $pid) instance has locked the build directory.
  If this is not the case, please delete _build/.lock
