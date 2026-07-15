A lockdir package depends on workspace package ws, which in turn depends on
workspace package aux:

consumer (lockdir) -> ws (workspace) -> aux (workspace)

  $ setup_workspace_fixture
  $ add_aux_workspace_fixture
  $ make_ws_depend_on_aux
  $ make_two_workspace_consumer ws

Only ws enters consumer's scoped layout. Package variables for the transitive
workspace dependency are unavailable:

  $ check_workspace_environment
  File "_build/_private/default/.lock/dune.lock/consumer.pkg", line 15, characters 19-35:
  15 |   (system "test -f %{pkg:aux:share}/data && echo aux-share-ok")
                          ^^^^^^^^^^^^^^^^
  Error: Undefined package variable: share
  File "dune.lock/consumer.pkg", line 16, characters 12-30:
  16 |   (run echo %{pkg:aux:version})))
                   ^^^^^^^^^^^^^^^^^^
  Error: Undefined package variable "version"
  [1]
