Split paths: consumer (L) -> ws (W), provider (L) -> aux (W).

  $ setup_workspace_fixture
  $ add_aux_workspace_fixture
  $ make_lockpkg provider <<EOF
  > (version 0.0.1)
  > (depends aux)
  > EOF
  $ make_two_workspace_consumer ws provider
  $ check_workspace_environment
  from-workspace-exe
  from-workspace-lib
  ws-share-ok
  1.2.3
  from-aux-workspace-exe
  from-aux-workspace-lib
  aux-share-ok
  2.3.4
