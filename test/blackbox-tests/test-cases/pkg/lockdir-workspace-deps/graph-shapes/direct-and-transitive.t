Duplicate paths: consumer (L) -> ws (W), provider (L) -> ws (W).

  $ setup_workspace_fixture
  $ make_lockpkg provider <<EOF
  > (version 0.0.1)
  > (depends ws)
  > EOF
  $ make_consumer ws provider
  $ check_workspace_environment
  from-workspace-exe
  from-workspace-lib
  share-ok
  ws
  1.2.3
  false
