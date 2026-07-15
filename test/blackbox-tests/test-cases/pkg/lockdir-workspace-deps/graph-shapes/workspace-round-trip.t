Round trip: app (W) -> consumer (L) -> ws (W).

  $ setup_workspace_fixture
  $ cat >> dune-project <<EOF
  > (package
  >  (name app)
  >  (allow_empty)
  >  (depends consumer))
  > EOF
  $ make_consumer ws
  $ check_workspace_environment
  from-workspace-exe
  from-workspace-lib
  share-ok
  ws
  1.2.3
  false
