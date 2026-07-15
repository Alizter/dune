Long locked chain: consumer (L) -> first (L) -> second (L) -> ws (W).

  $ setup_workspace_fixture
  $ make_lockpkg second <<EOF
  > (version 0.0.1)
  > (depends ws)
  > EOF
  $ make_lockpkg first <<EOF
  > (version 0.0.1)
  > (depends second)
  > EOF
  $ make_consumer first
  $ check_workspace_environment
  from-workspace-exe
  from-workspace-lib
  share-ok
  ws
  1.2.3
  false
