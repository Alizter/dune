  $ cat >test.ml <<EOF
  > (*TEST: assert (1 = 2) *)
  > EOF

  $ cat >dune-project <<EOF
  > (lang dune 2.6)
  > EOF

  $ cat >dune <<EOF
  > (library
  >  (name backend_simple)
  >  (modules ())
  >  (inline_tests.backend
  >   (generate_runner (run sed "s/(\\\\*TEST:\\\\(.*\\\\)\\\\*)/let () = if \\"%{inline_tests}\\" = \\"enabled\\" then \\\\1;;/" %{impl-files}))))
  > 
  > (library
  >  (name foo_simple)
  >  (inline_tests (backend backend_simple)))
  > 
  > (env
  >  (ignore-inline-tests (inline_tests ignored))
  >  (enable-inline-tests (inline_tests enabled))
  >  (disable-inline-tests (inline_tests disabled)))
  > EOF

  $ env -u OCAMLRUNPARAM dune runtest
  File "dune", line 9, characters 1-40:
  9 |  (inline_tests (backend backend_simple)))
       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Fatal error: exception File ".foo_simple.inline-tests/main.ml-gen", line 1, characters 40-46: Assertion failed
  [1]

Inline tests also generate an alias
  $ dune build @runtest-foo_simple
  File "dune", line 9, characters 1-40:
  9 |  (inline_tests (backend backend_simple)))
       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Fatal error: exception File ".foo_simple.inline-tests/main.ml-gen", line 1, characters 40-46: Assertion failed
  [1]

Make sure building both aliases doesn't build both
  $ dune build @runtest @lib-foo_simple
  Error: Alias "lib-foo_simple" specified on the command line is empty.
  It is not defined in . or any of its descendants.
  File "dune", line 9, characters 1-40:
  9 |  (inline_tests (backend backend_simple)))
       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Fatal error: exception File ".foo_simple.inline-tests/main.ml-gen", line 1, characters 40-46: Assertion failed
  [1]
This test demonstrates that the action is being run once
  $ cat _build/log | sed 's/\$ //g' | grep inline-test-runner 
  (cd _build/default && .foo_simple.inline-tests/inline-test-runner.exe)

The expected behavior for the following three tests is to output nothing: the tests are disabled or ignored.
  $ env -u OCAMLRUNPARAM dune runtest --profile release

  $ env -u OCAMLRUNPARAM dune runtest --profile disable-inline-tests

  $ env -u OCAMLRUNPARAM dune runtest --profile ignore-inline-tests

  $ env -u OCAMLRUNPARAM dune runtest --profile enable-inline-tests
  File "dune", line 9, characters 1-40:
  9 |  (inline_tests (backend backend_simple)))
       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Fatal error: exception File ".foo_simple.inline-tests/main.ml-gen", line 1, characters 40-46: Assertion failed
  [1]
