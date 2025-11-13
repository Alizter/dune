.. _howto-inline-tests:

******************
Using Inline Tests
******************

Inline tests are tests written directly inside the ``.ml`` files of a library.
They're ideal for unit testing functions and modules without leaving the source
file.

Overview
========

Inline tests use PPX rewriters to transform test annotations in your code into
executable tests. The most common framework is ppx_inline_test_, which provides
``let%test`` for simple assertions.

Basic Setup
===========

Step 1: Write Tests with ppx_inline_test
----------------------------------------

Add tests directly in your ``.ml`` files using the ``let%test`` syntax:

.. code:: ocaml

   let rec fact n = if n = 1 then 1 else n * fact (n - 1)

   let%test _ = fact 5 = 120

Step 2: Add PPX Preprocessor
----------------------------

Configure your library to use the ``ppx_inline_test`` preprocessor:

.. code:: dune

   (library
    (name foo)
    (preprocess (pps ppx_inline_test)))

Step 3: Enable Inline Tests
---------------------------

Tell Dune that your library contains inline tests by adding the
``inline_tests`` field:

.. code:: dune

   (library
    (name foo)
    (inline_tests)
    (preprocess (pps ppx_inline_test)))

Step 4: Run Tests
-----------------

Build and execute tests with:

.. code:: console

   $ dune runtest

If a test fails, you'll see an error message:

.. code:: console

   $ dune runtest
   [...]
   File "src/fact.ml", line 3, characters 0-25: <<(fact 5) = 0>> is false.

   FAILED 1 / 1 tests

Running Tests
=============

Run All Tests in a Library
--------------------------

Each inline test library generates an alias named ``runtest-<library-name>``.
You can run just that library's tests:

.. code:: console

   $ dune build @runtest-foo

Run Tests in a Directory
------------------------

Run all tests in a directory and its subdirectories:

.. code:: console

   $ dune runtest mylib/tests

Running Tests in Different Modes
================================

By default, Dune runs inline tests in native mode (or bytecode if native
compilation isn't available). You can customize this using the ``modes`` field.

Available Modes
---------------

- ``byte`` - run tests in bytecode
- ``native`` - run tests in native mode
- ``best`` - run in native with fallback to bytecode
- ``js`` - run tests in JavaScript using Node.js
- ``wasm`` - run tests in WebAssembly using Node.js

Example
-------

.. code:: dune

   (library
    (name foo)
    (inline_tests (modes byte best js wasm))
    (preprocess (pps ppx_inline_test)))

This will run the same tests in multiple modes, which is useful for ensuring
cross-platform compatibility.

Specifying Test Dependencies
============================

If your tests read files or depend on other build artifacts, declare them using
the ``deps`` field:

.. code:: dune

   (library
    (name foo)
    (inline_tests (deps data.txt config.json))
    (preprocess (pps ppx_inline_test)))

The ``deps`` field follows the :doc:`dependency specification
</concepts/dependency-spec>`, so you can use patterns, targets, and more:

.. code:: dune

   (library
    (name foo)
    (inline_tests
     (deps
      (glob_files test_data/*.txt)
      (alias test-fixtures)))
    (preprocess (pps ppx_inline_test)))

Passing Arguments to the Test Runner
====================================

Some test frameworks accept command-line flags. Pass them using the ``flags``
field:

.. code:: dune

   (library
    (name foo)
    (inline_tests (flags (-verbose -stop-on-error)))
    (preprocess (pps ppx_inline_test)))

The ``flags`` field follows the :doc:`Ordered Set Language
</reference/ordered-set-language>`, allowing you to use variables and
conditionals:

.. code:: dune

   (library
    (name foo)
    (inline_tests
     (flags (:standard -inline-test-runner %{library-name})))
    (preprocess (pps ppx_inline_test)))

Customizing the Test Executable
===============================

You can customize how the test executable is compiled using the ``executable``
sub-field.

Passing Compiler Flags
----------------------

.. code:: dune

   (library
    (name foo)
    (inline_tests
     (executable
      (flags (-w -27 -warn-error -A))))
    (preprocess (pps ppx_inline_test)))

Changing Link Flags
-------------------

The ``link_flags`` field controls flags passed to the linker. The default is
``-linkall``, which forces the linker to load your test modules (since the test
runner doesn't depend on them directly). You probably want to keep ``-linkall``:

.. code:: dune

   (library
    (name foo)
    (inline_tests
     (executable
      (link_flags -linkall -noautolink -cclib -Wl,-Bstatic -cclib -lm)))
    (preprocess (pps ppx_inline_test)))

The ``link_flags`` field supports ``(:include ...)`` forms for dynamic
configuration.

Using Additional Libraries in Tests
===================================

Sometimes tests need libraries that the main library doesn't use. This is
common with frameworks like qtest_, where tests are in comments. Specify
additional libraries with the ``libraries`` field:

.. code:: dune

   (library
    (name foo)
    (inline_tests
     (backend qtest.lib)
     (libraries test_helpers fixtures)))

This makes ``test_helpers`` and ``fixtures`` available to the test runner, but
not to the main library.

Using Different Backends
========================

By default, if you use ``ppx_inline_test``, Dune knows how to build and run
tests automatically because ppx_inline_test_ defines an inline tests backend.

However, some frameworks like qtest_ don't have built-in backends. For these,
specify the backend explicitly:

.. code:: dune

   (library
    (name foo)
    (inline_tests (backend qtest.lib)))

The backend name comes from the ``public_name`` field in the backend library's
dune file.

For frameworks that provide their own backend (like ppx_inline_test_ or
ppx_expect_), you don't need to specify a backend.

Testing Parameterised Libraries
===============================

If your library is parameterised (see :doc:`/reference/dune/library_parameter`),
you must specify which implementation of the parameters to use when running
inline tests. Use the ``arguments`` field to provide implementations for each
parameter.

For example, suppose ``foo`` is a parameterised library that takes parameters
``a_param`` and ``b_param``. You can specify the implementations of these
parameters for inline tests as follows:

.. code:: dune

   (library
    (name foo)
    (parameters a_param b_param)
    (inline_tests
     (arguments a_impl b_impl)))

The implementations ``a_impl`` and ``b_impl`` must be libraries that satisfy
the corresponding parameter interfaces.

Important Notes
===============

Dependencies on ppx_inline_test
-------------------------------

If you use ppx_inline_test_ in a package, that package must have an
*unconditional* dependency on ``ppx_inline_test`` in its opam file.
Don't use ``with-test`` for this dependency, as the library needs the PPX at
all times.

Multiple Test Files
-------------------

All ``.ml`` files in a library with ``inline_tests`` enabled will be scanned
for tests. Tests from all modules are combined into a single test executable
per library.

See Also
========

- :doc:`/reference/dune/inline-tests-field` - Complete field reference
- :doc:`/howto/expect-tests` - Using inline expectation tests
- :doc:`/howto/custom-inline-test-backend` - Creating custom backends
- :doc:`/explanation/testing-overview` - Overview of all test types

.. _ppx_inline_test: https://github.com/janestreet/ppx_inline_test
.. _ppx_expect:      https://github.com/janestreet/ppx_expect
.. _qtest:           https://github.com/vincent-hugot/qtest
