.. _howto-tests-stanza:

***************************
Using the test/tests Stanza
***************************

The ``test`` and ``tests`` stanzas define standalone test executables that run
as part of your test suite. This approach is ideal for integration tests,
executable testing, and tests that use frameworks like Alcotest or OUnit.

Overview
========

Unlike inline tests which are embedded in library code, tests defined with the
``test/tests`` stanzas are standalone executables. When you run ``dune
runtest``, these executables are built and executed.

The ``tests`` stanza is shorthand for defining multiple tests at once, while
``test`` defines a single test.

Basic Usage
===========

Single Test
-----------

Define a test executable with the ``test`` stanza:

.. code:: dune

   (test
    (name my_test))

This will build ``my_test.exe`` (from ``my_test.ml``) and run it when you
execute ``dune runtest``.

Multiple Tests
--------------

Define several tests at once with the ``tests`` stanza:

.. code:: dune

   (tests
    (names test1 test2 test3))

This is equivalent to writing three separate ``test`` stanzas, one for each
name.

When to Use test/tests
======================

Use the ``test`` or ``tests`` stanza when:

- Testing executable programs
- Integration testing across multiple modules
- Using test frameworks like Alcotest, OUnit, or QCheck
- Tests need dependencies not required by your library
- You want tests in separate files from implementation code

Writing Test Executables
=========================

Your test file is a regular OCaml program with a main entry point. The test
passes if the program exits with code 0, and fails otherwise.

Simple Example
--------------

``test_arithmetic.ml``:

.. code:: ocaml

   let () =
     assert (2 + 2 = 4);
     assert (10 - 5 = 5);
     print_endline "All tests passed!"

``dune``:

.. code:: dune

   (test
    (name test_arithmetic))

Using Test Frameworks
---------------------

Most test frameworks work by running tests and exiting with a non-zero code on
failure. For example, with Alcotest:

``test_mylib.ml``:

.. code:: ocaml

   let test_addition () =
     Alcotest.(check int) "same ints" 4 (2 + 2)

   let suite = [
     "arithmetic", [
       "addition", `Quick, test_addition;
     ];
   ]

   let () = Alcotest.run "MyLib" suite

``dune``:

.. code:: dune

   (test
    (name test_mylib)
    (libraries mylib alcotest))

See :doc:`/howto/test-with-alcotest` for more details on using Alcotest.

Expect Tests with .expected Files
==================================

The ``test/tests`` stanza has built-in support for expect-style testing. If a
file ``<test-name>.expected`` exists, Dune will:

1. Run the test executable
2. Capture its output
3. Compare it to ``<test-name>.expected``
4. Show a diff if they don't match

Example
-------

``hello.ml``:

.. code:: ocaml

   let () =
     print_endline "Hello, world!";
     print_endline "How are you?"

``hello.expected``:

.. code::

   Hello, world!
   How are you?

``dune``:

.. code:: dune

   (test
    (name hello))

Running the test:

.. code:: console

   $ dune runtest

If the output doesn't match, you'll see a diff. Accept the correction with:

.. code:: console

   $ dune promote

This workflow provides the same benefits as inline expect tests, but for
standalone executables.

Common Configuration
====================

Dependencies
------------

Specify libraries your test needs:

.. code:: dune

   (test
    (name my_test)
    (libraries mylib alcotest lwt.unix))

Files and Data Dependencies
----------------------------

If your test reads files, declare them as dependencies:

.. code:: dune

   (test
    (name my_test)
    (libraries mylib)
    (deps test_data.json config.toml))

Modules
-------

By default, a test uses the single module with its name. To include multiple
modules:

.. code:: dune

   (test
    (name integration_test)
    (modules integration_test test_helpers test_fixtures))

Conditional Tests
-----------------

Enable tests conditionally using ``enabled_if``:

.. code:: dune

   (test
    (name unix_specific_test)
    (enabled_if (= %{system} linux)))

Custom Test Action
------------------

Override how the test is run with the ``action`` field:

.. code:: dune

   (test
    (name my_test)
    (action (run %{test} --verbose --color=always)))

Compiler Flags
--------------

Pass flags to the OCaml compiler:

.. code:: dune

   (test
    (name my_test)
    (flags (-w -20 -warn-error -A)))

Test Aliases
============

Each test generates two aliases:

1. ``runtest`` - The standard test alias (run with ``dune runtest``)
2. ``runtest-<test-name>`` - A specific alias for just this test

Run a specific test:

.. code:: console

   $ dune build @runtest-my_test

Complete Example
================

Here's a complete example of a test suite using Alcotest:

``test/dune``:

.. code:: dune

   (tests
    (names test_parser test_evaluator test_integration)
    (libraries mylib alcotest)
    (deps test_data.txt))

``test/test_parser.ml``:

.. code:: ocaml

   let test_parse_number () =
     let open Mylib.Parser in
     Alcotest.(check (option int)) "parse valid number"
       (Some 42) (parse "42")

   let suite = [
     "parser", [
       "number parsing", `Quick, test_parse_number;
     ];
   ]

   let () = Alcotest.run "Parser" suite

``test/test_evaluator.ml``, ``test/test_integration.ml``:
Similar structure for other test suites.

Running tests:

.. code:: console

   $ dune runtest test/

This runs all three test executables.

Differences from Inline Tests
==============================

.. list-table::
   :header-rows: 1
   :widths: 30 35 35

   * - Feature
     - Inline Tests
     - test/tests Stanza
   * - Location
     - Inside library .ml files
     - Separate test files
   * - Use case
     - Unit testing library internals
     - Integration/executable testing
   * - Setup
     - Requires PPX rewriter
     - Plain OCaml executables
   * - Dependencies
     - Uses library's dependencies
     - Can have different dependencies
   * - Test organization
     - Distributed across modules
     - Centralized in test files

Best Practices
==============

Organize Tests in a Dedicated Directory
----------------------------------------

Keep tests in a ``test/`` directory separate from source code:

.. code::

   myproject/
     src/
       dune
       mylib.ml
     test/
       dune
       test_mylib.ml
       test_integration.ml

Use Descriptive Names
---------------------

Name test files and executables clearly:

- ``test_parser.ml`` instead of ``test1.ml``
- ``integration_network.ml`` instead of ``int.ml``

Separate Unit and Integration Tests
------------------------------------

Consider organizing tests by type:

.. code::

   test/
     unit/
       dune
       test_parser.ml
       test_evaluator.ml
     integration/
       dune
       test_end_to_end.ml

Test One Thing Per Executable
------------------------------

While possible to put all tests in one executable, smaller focused test
executables are easier to debug and faster to iterate on.

See Also
========

- :doc:`/reference/dune/test` - Complete stanza reference
- :doc:`/howto/test-with-alcotest` - Using Alcotest with tests
- :doc:`/howto/custom-test-rules` - Using rules for more control
- :doc:`/concepts/promotion` - Understanding diffing and promotion
- :doc:`/explanation/testing-overview` - Overview of all test types
