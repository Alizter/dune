The PID file can be empty while its owner is acquiring or releasing the build
lock. An empty PID must not prevent forwarding to a live RPC server.

  $ make_simple_rpc_watch_project
  $ start_dune

Keep the lock held, but reproduce the interval between truncating and writing
its PID file.

  $ : > _build/.lock
  $ dune build x
  Success

  $ stop_dune_quiet
