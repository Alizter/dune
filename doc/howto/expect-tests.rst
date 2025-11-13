.. _howto-expect-tests:

******************************
Using Inline Expectation Tests
******************************

Inline expectation tests (or expect tests) are a special type of inline test
where your code prints output followed by what you expect it to print. The test
framework captures the actual output and compares it to the expectation,
showing you a diff of any mismatches.

Overview
========

Expect tests use the ppx_expect_ preprocessor to transform ``[%expect]`` nodes
in your code into test assertions. When you run tests, the framework:

1. Executes your test code
2. Captures its output
3. Compares it to the expected output in ``[%expect{|...|});``
4. Shows a diff if there's a mismatch
5. Generates a correction file you can promote

This makes expect tests ideal for testing functions that produce complex or
multi-line output, like pretty-printers, formatters, or code generators.

Why Use Expect Tests?
=====================

Expect tests have several advantages:

- **Visual clarity**: The code, expectation, and outcome are clearly
  identified in one place
- **Easy maintenance**: Use ``dune promote`` to accept output changes rather
  than manually updating assertions
- **Good for complex output**: Multi-line or structured output is easy to
  express and review
- **Self-documenting**: The expected output serves as documentation

See `this blog post
<https://blog.janestreet.com/testing-with-expectations/>`_ for more about the
philosophy of expectation testing.

Basic Setup
===========

Step 1: Add ppx_expect Preprocessor
------------------------------------

Configure your library to use ppx_expect_:

.. code:: dune

   (library
    (name foo)
    (inline_tests)
    (preprocess (pps ppx_expect)))

Step 2: Write an Expect Test
-----------------------------

Use ``let%expect_test`` to define tests and ``[%expect{|...|};`` for
expectations:

.. code:: ocaml

   let%expect_test _ =
     print_endline "Hello, world!";
     [%expect{|
       Hello, world!
     |}]

The test code runs, prints output, and that output is compared to the contents
of the ``[%expect]`` block.

Step 3: Run Tests
------------------

Run tests with:

.. code:: console

   $ dune runtest

If the output matches, the test passes silently. If there's a mismatch, you'll
see a diff.

The Expect Test Workflow
=========================

Expect tests follow a specific workflow that makes them powerful for iterative
development.

1. Write the Test with Empty Expectations
------------------------------------------

Start by writing your test code with an empty ``[%expect]`` block:

.. code:: ocaml

   let rec fact n = if n = 1 then 1 else n * fact (n - 1)

   let%expect_test _ =
     print_int (fact 5);
     [%expect{||}]

2. Run the Tests
----------------

.. code:: console

   $ dune runtest

Dune will show a diff between the empty expectation and the actual output:

.. code:: console

   [...]
   -src/fact.ml
   +src/fact.ml.corrected
   File "src/fact.ml", line 5, characters 0-1:
   let rec fact n = if n = 1 then 1 else n * fact (n - 1)

   let%expect_test _ =
     print_int (fact 5);
   -  [%expect{||}]
   +  [%expect{| 120 |}]

3. Review and Promote the Correction
-------------------------------------

If the output is correct, accept it:

.. code:: console

   $ dune promote

This updates the source file with the generated correction. Your test now
looks like:

.. code:: ocaml

   let%expect_test _ =
     print_int (fact 5);
     [%expect{| 120 |}]

Automatic Promotion
-------------------

You can automatically accept corrections while running tests:

.. code:: console

   $ dune runtest --auto-promote

Use this carefully - always review the diffs before promoting.

Editor Integration
------------------

Some editors can promote corrections directly, making the workflow even
smoother. Check your editor's Dune integration for this feature.

Testing Complex Output
=======================

Expect tests excel at testing complex, multi-line output:

.. code:: ocaml

   let%expect_test "pretty print" =
     let data = [1; 2; 3; 4; 5] in
     List.iter (Printf.printf "Number: %d\n") data;
     [%expect{|
       Number: 1
       Number: 2
       Number: 3
       Number: 4
       Number: 5
     |}]

The vertical bars ``{|...|};`` create a "quoted string" that preserves
whitespace and newlines exactly as written, making it easy to express
multi-line expectations.

Testing Side Effects
====================

Expect tests capture anything printed to stdout. This makes them perfect for
testing code with output side effects:

.. code:: ocaml

   let%expect_test "logging" =
     log_info "Starting process";
     log_debug "Processing item 1";
     log_info "Process complete";
     [%expect{|
       [INFO] Starting process
       [DEBUG] Processing item 1
       [INFO] Process complete
     |}]

Comparing Multiple Outputs
===========================

You can have multiple ``[%expect]`` blocks in a single test:

.. code:: ocaml

   let%expect_test "stages" =
     print_endline "Stage 1";
     [%expect{| Stage 1 |}];

     print_endline "Stage 2";
     [%expect{| Stage 2 |}];

     print_endline "Complete";
     [%expect{| Complete |}]

Each ``[%expect]`` captures output since the previous one, making it easy to
test multi-stage processes.

Best Practices
==============

Keep Tests Focused
------------------

Each expect test should test one thing. Avoid cramming multiple unrelated
checks into a single test.

Use Descriptive Names
----------------------

Named tests are easier to debug:

.. code:: ocaml

   let%expect_test "factorial of 5" =
     print_int (fact 5);
     [%expect{| 120 |}]

   let%expect_test "factorial of 0 should be 1" =
     print_int (fact 0);
     [%expect{| 1 |}]

Review Diffs Carefully
----------------------

Before promoting, always review the diff to ensure changes are correct. Don't
blindly promote all changes.

Normalize Non-Deterministic Output
-----------------------------------

If your output includes timestamps, random values, or other non-deterministic
elements, normalize them in your test code before printing.

Combine with Regular Inline Tests
----------------------------------

Use regular inline tests (``let%test``) for simple boolean assertions and
expect tests for output verification. They work well together:

.. code:: dune

   (library
    (name foo)
    (inline_tests)
    (preprocess (pps ppx_inline_test ppx_expect)))

Advanced Configuration
======================

Expect tests support all the same configuration options as regular inline
tests. See :doc:`/howto/inline-tests` for details on:

- Running tests in different modes (bytecode, native, JavaScript, etc.)
- Specifying dependencies
- Passing flags to the test runner
- Using additional libraries
- Customizing the test executable

Just add your configuration to the ``inline_tests`` field as usual:

.. code:: dune

   (library
    (name foo)
    (inline_tests
     (modes native js)
     (deps test_data.json)
     (flags (-verbose)))
    (preprocess (pps ppx_expect)))

See Also
========

- :doc:`/howto/inline-tests` - General inline testing guide
- :doc:`/concepts/promotion` - Understanding the promotion mechanism
- :doc:`/reference/dune/inline-tests-field` - Complete field reference
- :doc:`/explanation/testing-overview` - Overview of all test types

.. _ppx_expect: https://github.com/janestreet/ppx_expect
