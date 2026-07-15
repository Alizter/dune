Multiple direct edges: consumer (L) -> ws (W), aux (W).

  $ setup_workspace_fixture
  $ add_aux_workspace_fixture
  $ make_two_workspace_consumer ws aux
  $ check_workspace_environment
  from-workspace-exe
  from-workspace-lib
  ws-share-ok
  1.2.3
  from-aux-workspace-exe
  from-aux-workspace-lib
  aux-share-ok
  2.3.4
