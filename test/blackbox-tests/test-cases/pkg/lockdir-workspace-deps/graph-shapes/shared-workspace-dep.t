Shared dependency: consumer (L) -> left (L), right (L), and both providers
depend on the same ws (W).

  $ setup_workspace_fixture
  $ make_lockpkg left <<EOF
  > (version 0.0.1)
  > (depends ws)
  > EOF
  $ make_lockpkg right <<EOF
  > (version 0.0.1)
  > (depends ws)
  > EOF
  $ make_consumer left right
  $ check_workspace_environment
  from-workspace-exe
  from-workspace-lib
  share-ok
  ws
  1.2.3
  false
