.. _howto-test-with-alcotest:

**********************
Testing with Alcotest
**********************

Alcotest is a lightweight and colorful OCaml test framework perfect for unit
and integration testing. It integrates seamlessly with Dune's ``test`` stanza.

Overview
========

Alcotest provides:

- Colorful test output
- Test organization into suites
- Rich set of comparison functions (``check``)
- Support for custom testable types
- Quick and slow test separation
- Good error messages with context

It's ideal for testing library internals, business logic, and any scenario
where you want structured test suites with clear pass/fail reporting.

Installation
============

Install Alcotest via opam:

.. code:: console

   $ opam install alcotest

Or add it to your project's dependencies in your ``.opam`` file:

.. code::

   depends: [
     "alcotest" {>= "1.7.0"}
   ]

Basic Setup
===========

Step 1: Create a Test File
---------------------------

Create a test file, typically in a ``test/`` directory:

``test/test_mylib.ml``:

.. code:: ocaml

   (* Open your library *)
   open Mylib

   (* Define a test *)
   let test_addition () =
     Alcotest.(check int) "1 + 1 equals 2" 2 (1 + 1)

   (* Group tests into a suite *)
   let suite = [
     "arithmetic", [
       "addition", `Quick, test_addition;
     ];
   ]

   (* Run the tests *)
   let () = Alcotest.run "MyLib" suite

Step 2: Configure Dune
----------------------

Add a ``test`` stanza to your ``test/dune`` file:

.. code:: dune

   (test
    (name test_mylib)
    (libraries mylib alcotest))

Step 3: Run Tests
-----------------

.. code:: console

   $ dune runtest

You'll see colorful output showing test results:

.. code:: console

   Testing MyLib.
   This run has ID `...`.

     [OK]          arithmetic          0   addition.

   Full test results in `...`.
   Test Successful in 0.001s. 1 test run.

Writing Tests
=============

Test Structure
--------------

Alcotest tests follow this structure:

.. code:: ocaml

   let test_function () =
     let expected = <expected-value> in
     let actual = <function-to-test> in
     Alcotest.(check <testable>) "description" expected actual

The basic check function signature is:

.. code:: ocaml

   val check : 'a testable -> string -> 'a -> 'a -> unit

Where:
- ``testable`` - Type of values being compared
- ``string`` - Test description (shown on failure)
- First ``'a`` - Expected value
- Second ``'a`` - Actual value

Common Testable Types
---------------------

Alcotest provides built-in testable types:

.. code:: ocaml

   (* Basic types *)
   Alcotest.(check int) "same ints" 42 (6 * 7)
   Alcotest.(check string) "same strings" "hello" greeting
   Alcotest.(check bool) "is true" true condition
   Alcotest.(check (float epsilon)) "same floats" 3.14 pi

   (* Container types *)
   Alcotest.(check (list int)) "same lists" [1; 2; 3] result
   Alcotest.(check (option string)) "same options" (Some "x") maybe_x
   Alcotest.(check (result int string)) "is ok" (Ok 42) computation

   (* Other built-ins *)
   Alcotest.(check unit) "returns unit" () (side_effect_fn ())
   Alcotest.(check char) "same char" 'a' first_char
   Alcotest.(check int32) "same int32" 42l value
   Alcotest.(check int64) "same int64" 42L value

Multiple Assertions
-------------------

A single test can have multiple checks:

.. code:: ocaml

   let test_parser () =
     let result = parse "x = 42" in
     match result with
     | Some { var; value } ->
         Alcotest.(check string) "variable name" "x" var;
         Alcotest.(check int) "variable value" 42 value
     | None ->
         Alcotest.fail "parsing failed"

Organizing Tests
================

Test Suites
-----------

Organize tests into named suites:

.. code:: ocaml

   let suite = [
     "suite1", [
       "test1", `Quick, test_function_1;
       "test2", `Quick, test_function_2;
     ];
     "suite2", [
       "test3", `Quick, test_function_3;
       "test4", `Slow, slow_test_function;
     ];
   ]

Test Speed
----------

Mark tests as ``Quick`` or ``Slow``:

- ``Quick`` - Runs by default
- ``Slow`` - Only runs when explicitly requested

Run only quick tests (default):

.. code:: console

   $ dune runtest

Run all tests including slow ones:

.. code:: console

   $ alcotest-runner test_mylib.exe

Multiple Test Files
-------------------

Organize tests across multiple files:

.. code::

   test/
     dune
     test_parser.ml    - Parser tests
     test_evaluator.ml - Evaluator tests
     test_utils.ml     - Utility tests

Each file has its own test suite and ``Alcotest.run`` call.

Custom Testable Types
=====================

For custom types, create a testable:

.. code:: ocaml

   type color = Red | Green | Blue

   let color_testable =
     let pp fmt = function
       | Red -> Format.fprintf fmt "Red"
       | Green -> Format.fprintf fmt "Green"
       | Blue -> Format.fprintf fmt "Blue"
     in
     let equal = ( = ) in
     Alcotest.testable pp equal

   let test_color () =
     Alcotest.(check color_testable) "is red" Red get_color

For types with built-in pretty-printers:

.. code:: ocaml

   type point = { x : int; y : int }

   let pp_point fmt { x; y } =
     Format.fprintf fmt "(%d, %d)" x y

   let point_testable =
     Alcotest.testable pp_point ( = )

Using ``of_pp`` for Simpler Cases
----------------------------------

If you only have a pretty-printer:

.. code:: ocaml

   let point_testable = Alcotest.of_pp pp_point

This uses structural equality ``(=)`` by default.

Testing Exceptions
==================

Test that code raises exceptions:

.. code:: ocaml

   let test_div_by_zero () =
     Alcotest.check_raises
       "division by zero"
       Division_by_zero
       (fun () -> ignore (10 / 0))

Or test the exception value:

.. code:: ocaml

   exception Custom_error of string

   let test_custom_error () =
     let expected_exn = Custom_error "bad input" in
     Alcotest.check_raises
       "raises custom error"
       expected_exn
       (fun () -> process_input "invalid")

Failing Tests Explicitly
=========================

Force a test failure:

.. code:: ocaml

   let test_not_implemented () =
     Alcotest.fail "This test is not yet implemented"

   let test_should_not_reach () =
     match dangerous_operation () with
     | Some result -> process result
     | None -> Alcotest.fail "Operation should have succeeded"

Test Fixtures and Setup
========================

Shared Test Data
----------------

Use regular OCaml bindings:

.. code:: ocaml

   let test_data = [1; 2; 3; 4; 5]

   let test_sum () =
     Alcotest.(check int) "sum of test data" 15 (List.fold_left (+) 0 test_data)

   let test_length () =
     Alcotest.(check int) "length of test data" 5 (List.length test_data)

Setup and Teardown
------------------

Use higher-order functions:

.. code:: ocaml

   let with_temp_file test () =
     let filename = Filename.temp_file "test" ".txt" in
     Fun.protect
       ~finally:(fun () -> Sys.remove filename)
       (fun () -> test filename)

   let test_file_writing =
     with_temp_file (fun filename ->
       Out_channel.with_open_text filename (fun oc ->
         output_string oc "test");
       let content = In_channel.with_open_text filename In_channel.input_all in
       Alcotest.(check string) "file content" "test" content)

   let suite = [
     "file operations", [
       "writing", `Quick, test_file_writing;
     ];
   ]

Parameterized Tests
===================

Test the same logic with different inputs:

.. code:: ocaml

   let test_factorial ~input ~expected () =
     Alcotest.(check int)
       (Printf.sprintf "factorial(%d)" input)
       expected
       (factorial input)

   let factorial_tests = [
     "factorial", [
       "factorial(0)", `Quick, test_factorial ~input:0 ~expected:1;
       "factorial(1)", `Quick, test_factorial ~input:1 ~expected:1;
       "factorial(5)", `Quick, test_factorial ~input:5 ~expected:120;
       "factorial(10)", `Quick, test_factorial ~input:10 ~expected:3628800;
     ];
   ]

Or generate tests from data:

.. code:: ocaml

   let test_cases = [
     (0, 1);
     (1, 1);
     (5, 120);
     (10, 3628800);
   ]

   let factorial_tests =
     let make_test (input, expected) =
       ( Printf.sprintf "factorial(%d)" input,
         `Quick,
         fun () ->
           Alcotest.(check int)
             (Printf.sprintf "factorial(%d) = %d" input expected)
             expected
             (factorial input) )
     in
     "factorial", List.map make_test test_cases

Complete Example
================

Here's a complete example testing a simple library:

``lib/calculator.ml``:

.. code:: ocaml

   type value =
     | Int of int
     | Float of float

   let as_float = function
     | Int n -> float_of_int n
     | Float f -> f

   let add a b =
     Float (as_float a +. as_float b)

``test/test_calculator.ml``:

.. code:: ocaml

   open Calculator

   (* Define testable for value type *)
   let value_testable =
     let pp fmt = function
       | Int n -> Format.fprintf fmt "Int %d" n
       | Float f -> Format.fprintf fmt "Float %f" f
     in
     Alcotest.testable pp ( = )

   (* Test as_float *)
   let test_as_float_int () =
     let result = as_float (Int 42) in
     Alcotest.(check (float epsilon_float)) "int to float" 42.0 result

   let test_as_float_float () =
     let result = as_float (Float 3.14) in
     Alcotest.(check (float epsilon_float)) "float to float" 3.14 result

   (* Test add *)
   let test_add_ints () =
     let result = add (Int 2) (Int 3) in
     Alcotest.(check value_testable) "add ints" (Float 5.0) result

   let test_add_mixed () =
     let result = add (Int 2) (Float 3.5) in
     Alcotest.(check value_testable) "add mixed" (Float 5.5) result

   (* Test suite *)
   let suite = [
     "as_float", [
       "int", `Quick, test_as_float_int;
       "float", `Quick, test_as_float_float;
     ];
     "add", [
       "two ints", `Quick, test_add_ints;
       "mixed types", `Quick, test_add_mixed;
     ];
   ]

   let () = Alcotest.run "Calculator" suite

``test/dune``:

.. code:: dune

   (test
    (name test_calculator)
    (libraries calculator alcotest))

Advanced Features
=================

Filtering Tests
---------------

Run tests matching a pattern:

.. code:: console

   $ dune exec ./test/test_calculator.exe -- test 'add'

Run a specific test:

.. code:: console

   $ dune exec ./test/test_calculator.exe -- test 'add' 'two ints'

Verbose Output
--------------

See more detail about passing tests:

.. code:: console

   $ dune exec ./test/test_calculator.exe -- --verbose

Test Output Files
-----------------

Alcotest creates result files in ``_build/_tests/``. These contain detailed
logs of test runs.

Best Practices
==============

Use Descriptive Test Names
---------------------------

Good names help identify failures:

.. code:: ocaml

   (* Good *)
   "parse returns None for empty string", `Quick, test_parse_empty

   (* Less good *)
   "test1", `Quick, test1

Test One Thing Per Test
------------------------

Keep tests focused:

.. code:: ocaml

   (* Good - focused *)
   let test_addition () = ...
   let test_subtraction () = ...

   (* Less good - too much in one test *)
   let test_all_arithmetic () = ...

Use Appropriate Testables
--------------------------

Create custom testables for domain types rather than comparing strings:

.. code:: ocaml

   (* Good *)
   Alcotest.(check ast_testable) "parse result" expected_ast parsed

   (* Less good *)
   Alcotest.(check string) "parse result" (show_ast expected) (show_ast parsed)

Organize Tests Logically
-------------------------

Group related tests into suites:

.. code:: ocaml

   let suite = [
     "parsing", parsing_tests;
     "evaluation", evaluation_tests;
     "pretty-printing", pp_tests;
   ]

Comparison with Other Approaches
=================================

.. list-table::
   :header-rows: 1
   :widths: 25 25 25 25

   * - Feature
     - Alcotest
     - Inline Tests
     - Cram Tests
   * - Best for
     - Unit tests
     - Library internals
     - CLI tools
   * - Test location
     - Separate files
     - In source files
     - .t files
   * - Setup complexity
     - Medium
     - Low (with PPX)
     - Low
   * - Output format
     - Colorful terminal
     - Build output
     - Shell session
   * - IDE integration
     - Via test stanza
     - Via inline_tests
     - Via .t files

See Also
========

- :doc:`/howto/tests-stanza` - More on the test stanza
- :doc:`/reference/dune/test` - Test stanza reference
- :doc:`/explanation/testing-overview` - Overview of all testing approaches
- `Alcotest documentation <https://github.com/mirage/alcotest>`_ - Official docs
- :doc:`/tutorials/developing-with-dune/unit-tests` - Tutorial using Alcotest
