.. _howto-custom-inline-test-backend:

************************************
Creating Custom Inline Test Backends
************************************

If you're writing a test framework or need to integrate a test library with
Dune's inline tests, you can define a custom inline test backend. This allows
your framework to work seamlessly with Dune's ``inline_tests`` field.

Overview
========

An inline test backend tells Dune how to:

1. Generate a test runner from library source files
2. Build the test runner
3. Execute the test runner
4. Optionally partition tests for parallel execution

Once defined, users can reference your backend in their libraries:

.. code:: dune

   (library
    (name mylib)
    (inline_tests (backend my_test_framework)))

When to Create a Backend
=========================

Create a custom backend when:

- You're writing a new test framework
- Integrating an existing framework (like qtest_) that doesn't have a backend
- Your framework needs custom test runner generation
- You want users to avoid manual test configuration

You **don't** need a backend if:

- You're just using an existing framework (like ppx_inline_test_)
- You can use the ``test`` stanza instead
- Your tests don't need inline integration

How Backends Work
=================

When a library has ``inline_tests`` enabled with a backend, Dune:

1. Calls the backend's ``generate_runner`` action to create test runner code
2. Compiles that code along with the ``runner_libraries``
3. Links the test executable
4. Runs it with the specified ``flags``

The test runner is generated based on information about the library (its name,
source files, etc.).

Defining a Backend
==================

Add an ``inline_tests.backend`` field to your framework's library:

.. code:: dune

   (library
    (name my_test_framework)
    (public_name my_test_framework)
    (inline_tests.backend
     (generate_runner <action>)
     (runner_libraries (<dependencies>))
     (flags (<flags>))
     (list_partitions_flags (<flags>))  ; optional
     (extends (<backends>))))            ; optional

Backend Fields
==============

generate_runner
---------------

An action that generates test runner code on stdout. This action runs in the
library's directory and can use special variables:

Available Variables:

- ``%{library-name}`` - Name of the library being tested
- ``%{impl-files}`` - List of ``.ml`` and ``.re`` implementation files
- ``%{intf-files}`` - List of ``.mli`` and ``.rei`` interface files

Example:

.. code:: dune

   (generate_runner
    (run my_test_generator --lib=%{library-name} %{impl-files}))

The action should output valid OCaml code that will serve as the test runner's
main module.

runner_libraries
----------------

Libraries the generated test runner needs. These are linked into the test
executable.

Example:

.. code:: dune

   (runner_libraries (my_test_framework base))

If your ``generate_runner`` outputs code like:

.. code:: ocaml

   let () = My_test_framework.run_all_tests ()

Then ``my_test_framework`` should be in ``runner_libraries``.

flags
-----

Command-line flags to pass when running the test executable.

Example:

.. code:: dune

   (flags (-verbose))

You can use the ``%{library-name}`` variable:

.. code:: dune

   (flags (--test-suite=%{library-name}))

If your backend supports partitions, you can also use ``%{partition}``:

.. code:: dune

   (flags (--partition=%{partition}))

list_partitions_flags
---------------------

(Optional) Flags to pass when listing available test partitions. Only needed if
your backend supports parallel test execution via partitions.

Example:

.. code:: dune

   (list_partitions_flags (--list-partitions))

When Dune runs the test executable with these flags, it should output partition
names (one per line). Dune will then run the tests multiple times in parallel,
once for each partition, using the partition name in the ``flags`` field.

extends
-------

(Optional) Other backends this backend extends. Used when your backend builds
on another framework.

Example:

.. code:: dune

   (extends (ppx_inline_test))

Extending Backends:

- A library can use multiple backends, but exactly one must be a "root" backend
  (not extending another)
- Fields from all backends are concatenated
- If backend ``b`` extends backend ``a``, then ``a`` is processed before ``b``

Example: ppx_expect_ extends ppx_inline_test_.

Simple Example
==============

Let's create a simple backend for tests in comments.

Test Syntax
-----------

Tests are written in comments:

.. code:: ocaml

   (*TEST: assert (fact 5 = 120) *)

Backend Definition
------------------

.. code:: dune

   (library
    (name simple_tests)
    (inline_tests.backend
     (generate_runner
      (run sed "s/(\\*TEST:\\(.*\\)\\*)/let () = \\1;;/" %{impl-files}))))

This uses ``sed`` to extract tests from comments and generate a test runner.

**Note**: This is only an example. Using ``sed`` in builds causes portability
problems. Real implementations should use OCaml tools.

How It Works
------------

Given a library with this code:

.. code:: ocaml

   (* lib.ml *)
   let rec fact n = if n = 1 then 1 else n * fact (n - 1)

   (*TEST: assert (fact 5 = 120) *)

The ``generate_runner`` action transforms it to:

.. code:: ocaml

   let () = assert (fact 5 = 120);;

Dune compiles this as the test runner and executes it.

Realistic Example
=================

A more realistic backend using a custom test generator:

Backend Library
---------------

``my_framework/dune``:

.. code:: dune

   (library
    (name my_test_framework)
    (public_name my_test_framework))

   (executable
    (name generator)
    (public_name my-test-generator)
    (libraries my_test_framework compiler-libs.common))

   (library
    (name my_test_framework)
    (public_name my_test_framework)
    (inline_tests.backend
     (generate_runner (run my-test-generator %{impl-files}))
     (runner_libraries (my_test_framework))
     (flags (-color=always -verbose))))

Generator Implementation
------------------------

``my_framework/generator.ml``:

.. code:: ocaml

   (* Parses source files and extracts tests *)
   let extract_tests filename =
     (* Parse the file using compiler-libs *)
     (* Find test annotations/attributes *)
     (* Return list of test names *)
     ...

   let () =
     let files = List.tl (Array.to_list Sys.argv) in
     let tests = List.concat_map extract_tests files in

     (* Generate test runner code *)
     Printf.printf "let () =\n";
     Printf.printf "  let tests = [\n";
     List.iter (fun test ->
       Printf.printf "    %S, (fun () -> %s);\n" test.name test.code
     ) tests;
     Printf.printf "  ] in\n";
     Printf.printf "  My_test_framework.run tests\n"

Using the Backend
-----------------

Users can now use your framework:

.. code:: dune

   (library
    (name my_library)
    (inline_tests (backend my_test_framework))
    (preprocess (pps my_test_framework.ppx)))  ; if you have a PPX

Supporting Test Partitions
===========================

For parallel test execution, implement partition support:

Backend Configuration
---------------------

.. code:: dune

   (inline_tests.backend
    (generate_runner (run my-test-generator %{impl-files}))
    (runner_libraries (my_test_framework))
    (flags (--partition=%{partition}))
    (list_partitions_flags (--list-partitions)))

Runner Implementation
---------------------

Your test runner should:

1. With ``--list-partitions``: Output partition names (one per line)
2. With ``--partition=<name>``: Run only tests in that partition

.. code:: ocaml

   let () =
     match Sys.argv with
     | [| _; "--list-partitions" |] ->
         List.iter print_endline ["partition1"; "partition2"; "partition3"]
     | [| _; partition_flag |] ->
         let partition = String.split_on_char '=' partition_flag |> List.nth 1 in
         run_tests_in_partition partition
     | _ ->
         run_all_tests ()

Dune will then run your tests in parallel across the partitions.

Extending Existing Backends
============================

To extend an existing backend (like adding features to ppx_inline_test_):

.. code:: dune

   (library
    (name my_enhanced_tests)
    (public_name my_enhanced_tests)
    (inline_tests.backend
     (extends (ppx_inline_test))
     (runner_libraries (my_enhanced_tests))
     (flags (--my-extra-flag))))

This combines your backend's configuration with ppx_inline_test_'s.

Best Practices
==============

Use OCaml Tools, Not Shell Scripts
-----------------------------------

Avoid using ``sed``, ``awk``, or shell scripts in ``generate_runner``. They
cause portability problems. Use OCaml tools instead.

Generate Readable Code
----------------------

The generated test runner should be readable for debugging. Users may need to
examine it when tests fail.

Report Clear Errors
-------------------

If test generation fails (e.g., syntax errors in test annotations), report
clear, actionable errors with file/line information.

Document Your Backend
---------------------

Explain:
- How to write tests for your framework
- What PPX rewriters are needed (if any)
- What options are available
- How to reference the backend in dune files

Provide Good Defaults
----------------------

Choose sensible defaults for ``flags`` so users get a good experience without
configuration.

Testing Your Backend
====================

Test your backend thoroughly:

1. Create a library using your backend
2. Write tests in your framework's syntax
3. Run ``dune build @runtest`` and verify it works
4. Test with multiple source files
5. Test error cases (invalid test syntax, etc.)
6. Test with ``dune promote`` if using expect-style testing

See Also
========

- :doc:`/reference/dune/inline-tests-backend` - Complete field reference
- :doc:`/howto/inline-tests` - Using inline tests
- :doc:`/reference/actions/index` - Available actions for generate_runner
- :doc:`/explanation/testing-overview` - Overview of testing in Dune

.. _ppx_inline_test: https://github.com/janestreet/ppx_inline_test
.. _ppx_expect:      https://github.com/janestreet/ppx_expect
.. _qtest:           https://github.com/vincent-hugot/qtest
