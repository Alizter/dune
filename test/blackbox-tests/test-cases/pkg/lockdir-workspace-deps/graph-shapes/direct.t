Direct edge: consumer (L) -> ws (W).

  $ setup_workspace_fixture
  $ make_consumer ws
  $ check_workspace_environment
  from-workspace-exe
  from-workspace-lib
  share-ok
  ws
  1.2.3
  false
