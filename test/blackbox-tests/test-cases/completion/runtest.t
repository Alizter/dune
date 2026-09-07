Test semantic shell completion for `dune runtest`.

Completion failures are not hidden by the protocol parser.

  $ DUNE_COMPLETE_BIN=false dune_complete runtest ""
  [1]

  $ make_dune_project 3.21

Set up a mixed tree: cram tests, ml tests, a subdir that itself contains a
nested cram test, and a sibling subdir with no tests.

  $ mkdir -p with_tests with_tests/nested without_tests
  $ cat > with_tests/foo.t <<'EOF'
  >   $ echo foo
  >   foo
  > EOF
  $ cat > with_tests/nested/bar.t <<'EOF'
  >   $ echo bar
  >   bar
  > EOF
  $ cat > with_tests/dune <<EOF
  > (tests
  >  (names test_a test_b)
  >  (modules test_a test_b))
  > (library
  >  (name inline_lib)
  >  (modules inline_lib)
  >  (inline_tests)
  >  (preprocess (pps ppx_expect)))
  > EOF
  $ cat > with_tests/test_a.ml <<EOF
  > let () = print_endline "a"
  > EOF
  $ cat > with_tests/test_b.ml <<EOF
  > let () = print_endline "b"
  > EOF
  $ cat > with_tests/inline_lib.ml <<'EOF'
  > let%expect_test _ = ()
  > EOF
  $ cat > top.t <<'EOF'
  >   $ echo top
  >   top
  > EOF

Option suggestions are only included when the token starts with a dash.

  $ dune --__complete runtest --__complete= | grep -x Options
  [1]
  $ dune --__complete runtest --__complete=- | grep -x Options
  Options

Completion evaluates candidates inside a build-system run without creating the
default trace on every invocation. An explicit trace remains available for
diagnosing slow completion.

  $ dune_complete runtest "" >/dev/null
  $ test ! -e _build/trace.csexp
  $ dune_complete runtest --trace-file completion-trace.csexp "" >/dev/null
  $ dune trace cat --trace-file completion-trace.csexp |
  >   jq -r 'select(.cat == "build") | .name'
  build-start
  build-finish

Completing on "with_tests/" lists its cram tests, ml tests, and subdirs:

  $ dune_complete runtest "with_tests/"
  with_tests/foo.t
  with_tests/inline_lib.ml
  with_tests/nested/
  with_tests/test_a.ml
  with_tests/test_b.ml

Completing on "with_tests/test" narrows by basename prefix:

  $ dune_complete runtest "with_tests/test"
  with_tests/test_a.ml
  with_tests/test_b.ml

Directories are offered without recursively searching them for tests. Once a
directory is entered, completion only discovers the tests in that directory.

  $ dune_complete runtest ""
  top.t
  with_tests/
  without_tests/

A bogus parent yields nothing and doesn't crash:

  $ dune_complete runtest "does/not/exist/"

Invoking completion from outside the workspace root also yields nothing:

  $ project_root="$PWD"
  $ (cd .. && dune_complete runtest --root "$project_root" "")

Completion paths are relative to the directory where dune was invoked:

  $ (cd with_tests && dune_complete runtest --root .. "")
  foo.t
  inline_lib.ml
  nested/
  test_a.ml
  test_b.ml

  $ (cd with_tests && dune_complete runtest --root .. "nested/")
  nested/bar.t

Completion is best-effort while a watch server is actively building. It must
return promptly without cancelling or restarting the active build.

  $ marker_dir="$(mktemp -d)"
  $ starts="$marker_dir/starts"
  $ release="$marker_dir/release"
  $ cat > dune <<EOF
  > (rule
  >  (alias hold)
  >  (action
  >   (bash
  >    "echo started >> '$starts'
  >     while [ ! -e '$release' ]; do sleep 0.05; done")))
  > EOF

  $ dune build @hold --watch > .#dune-output 2>&1 &
  $ DUNE_PID=$!
  $ export DUNE_RUNNING=1
  $ wait_for_rpc_server
  $ with_timeout dune_cmd wait-for-file-to-appear "$starts"

  $ dune_complete runtest ""
  $ wc -l < "$starts"
  1
  $ with_timeout dune rpc ping
  Server appears to be responding normally

  $ touch "$release"
  $ stop_dune_quiet

Batch builds also run an RPC server, but without build-loop handling. Completion
falls back immediately instead of waiting for the batch build to finish.

  $ starts="$marker_dir/batch-starts"
  $ release="$marker_dir/batch-release"
  $ cat > dune <<EOF
  > (rule
  >  (alias batch-hold)
  >  (action
  >   (bash
  >    "echo started >> '$starts'
  >     while [ ! -e '$release' ]; do sleep 0.05; done")))
  > EOF
  $ dune build @batch-hold > batch.out 2>&1 &
  $ BATCH_PID=$!
  $ with_timeout dune_cmd wait-for-file-to-appear "$starts"

  $ dune_complete runtest ""
  $ wc -l < "$starts"
  1
  $ with_timeout dune rpc ping
  Server appears to be responding normally

  $ touch "$release"
  $ if wait_for_pid_to_exit_with_timeout "$BATCH_PID" 200; then
  >   wait "$BATCH_PID"
  > else
  >   cat batch.out
  >   kill "$BATCH_PID"
  >   wait "$BATCH_PID"
  > fi
  $ rm -rf "$marker_dir"

Completion uses the initialized build graph of a running watch server. Give
the server and the completion client different environments so this cannot
accidentally pass by initializing a second build graph in the client.

  $ cat > dune <<'EOF'
  > (test
  >  (name server_only)
  >  (build_if %{env:SERVER_TESTS=false}))
  > EOF
  $ cat > server_only.ml <<'EOF'
  > let () = ()
  > EOF

  $ export SERVER_TESTS=true
  $ start_dune
  $ export SERVER_TESTS=false

The request also flushes pending watcher events before looking up candidates.

  $ cat > added_after_start.t <<'EOF'
  >   $ true
  > EOF
  $ dune_complete runtest ""
  added_after_start.t
  server_only.ml
  top.t
  with_tests/
  without_tests/

The completion request leaves the watch server responsive.

  $ with_timeout dune rpc ping
  Server appears to be responding normally
  $ stop_dune_quiet

Like `dune runtest` itself, completion does not choose an arbitrary context
when a workspace has several contexts and none is named `default`.

  $ mkdir ambiguous-context
  $ cat > ambiguous-context/dune-project <<'EOF'
  > (lang dune 3.21)
  > EOF
  $ cat > ambiguous-context/dune-workspace <<'EOF'
  > (lang dune 3.21)
  > (context (default (name one)))
  > (context (default (name two)))
  > EOF
  $ cat > ambiguous-context/test.t <<'EOF'
  >   $ true
  > EOF
  $ (cd ambiguous-context && dune_complete runtest "")
