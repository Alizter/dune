.. _dune-reference-test:

test
----

The ``test`` stanza defines a single test executable that runs as part of the
``runtest`` alias.

Syntax
~~~~~~

.. code:: dune

   (test
    (name <name>)
    <optional-fields>)

The ``name`` field specifies the test name and is used to determine the
executable name (``<name>.exe``) and the test-specific alias
(``runtest-<name>``).

**See also**: :doc:`/howto/tests-stanza` for usage guide.

.. _tests-stanza:

tests
-----

The ``tests`` stanza defines multiple test executables at once. It's equivalent
to writing multiple ``test`` stanzas with the same optional fields.

Syntax
~~~~~~

.. code:: dune

   (tests
    (names <name1> <name2> ...)
    <optional-fields>)

Example
~~~~~~~

.. code:: dune

   (tests
    (names test_parser test_evaluator test_printer)
    (libraries mylib alcotest))

This defines three test executables: ``test_parser.exe``,
``test_evaluator.exe``, and ``test_printer.exe``.

Common Fields
-------------

Both ``test`` and ``tests`` stanzas support the same optional fields, which are
a subset of the :ref:`executables stanza <shared-exe-fields>` fields. All
fields except ``public_names`` are supported.

name / names
~~~~~~~~~~~~

**Required field**.

For ``test``:

.. code:: dune

   (name <test-name>)

For ``tests``:

.. code:: dune

   (names <test-name1> <test-name2> ...)

The name determines:

1. The test executable name: ``<name>.exe``
2. The test-specific alias: ``runtest-<name>``
3. The source file name: ``<name>.ml`` (by default)

libraries
~~~~~~~~~

.. code:: dune

   (libraries <library-names>)

Libraries to link into the test executable.

**Example**:

.. code:: dune

   (test
    (name test_mylib)
    (libraries mylib alcotest lwt.unix))

modules
~~~~~~~

.. code:: dune

   (modules <module-names>)

Modules to include in the test executable. By default, only the module matching
the test name is included.

**Example**:

.. code:: dune

   (test
    (name integration_test)
    (modules integration_test test_helpers test_fixtures))

deps
~~~~

.. code:: dune

   (deps <dep-spec>)

Dependencies required by the test. Uses the standard :doc:`dependency
specification </concepts/dependency-spec>`.

**Example**:

.. code:: dune

   (test
    (name test_parser)
    (deps test_data.json (glob_files fixtures/*.txt)))

flags
~~~~~

.. code:: dune

   (flags <flags>)

Compiler flags for building the test executable. Uses the
:doc:`/reference/ordered-set-language`.

**Example**:

.. code:: dune

   (test
    (name test_mylib)
    (flags (-w -27 -warn-error -A)))

enabled_if
~~~~~~~~~~

.. code:: dune

   (enabled_if <condition>)

Conditionally enable *running* the test. The test executable is still built
even when the condition is false.

**Example**:

.. code:: dune

   (test
    (name unix_test)
    (enabled_if (<> %{system} windows)))

**Important**: This only affects test execution, not compilation. To
conditionally build the executable, use ``build_if``.

**See also**: :doc:`/reference/boolean-language`

build_if
~~~~~~~~

.. code:: dune

   (build_if <condition>)

Conditionally build and run the test executable.

**Example**:

.. code:: dune

   (test
    (name optional_test)
    (build_if %{lib-available:optional_dep}))

**Difference from enabled_if**: ``build_if`` affects both building and running,
while ``enabled_if`` only affects running.

**See also**: :doc:`/reference/boolean-language`

action
~~~~~~

.. code:: dune

   (action <action>)

Override how the test is invoked. By default, tests are run as ``<name>.exe``
with no arguments.

**Example**:

.. code:: dune

   (test
    (name test_alcotest)
    (libraries alcotest mylib)
    (action (run %{test} -e --color=always)))

The ``%{test}`` variable refers to the test executable path.

**Common use cases**:

- Passing flags to test frameworks
- Running tests with wrappers
- Customizing test invocation

**See also**: :doc:`/reference/actions/index`

preprocess
~~~~~~~~~~

.. code:: dune

   (preprocess <preprocess-spec>)

Preprocessing for test files.

**Example**:

.. code:: dune

   (test
    (name test_ppx)
    (preprocess (pps ppx_deriving.show)))

**See also**: :doc:`/reference/dune/library` (preprocess field)

Other Fields
~~~~~~~~~~~~

Additional fields from the :ref:`executables stanza <shared-exe-fields>` are
supported, including:

- ``preprocessor_deps``
- ``lint``
- ``modes``
- ``link_flags``
- ``link_deps``
- ``foreign_stubs``
- ``foreign_archives``
- ``js_of_ocaml``
- ``package``
- ``locks``

**See**: :ref:`executables stanza <shared-exe-fields>` for full field list.

Expect Tests
------------

If a file ``<test-name>.expected`` exists alongside the test, Dune automatically
sets up an expect test:

1. The test executable runs
2. Its output is captured
3. The output is compared to ``<test-name>.expected``
4. On mismatch, a diff is shown

**Example**:

Files:

.. code::

   test/
     hello_test.ml
     hello_test.expected
     dune

``dune``:

.. code:: dune

   (test
    (name hello_test))

``hello_test.expected``:

.. code::

   Hello, world!

When the test runs, if it prints anything other than "Hello, world!", Dune
shows a diff. Use ``dune promote`` to accept the new output.

**See also**: :doc:`/howto/tests-stanza`, :doc:`/concepts/promotion`

Generated Aliases
-----------------

Each test generates aliases:

1. ``@runtest`` - The standard test alias (all tests)
2. ``@runtest-<name>`` - Test-specific alias

**Running specific tests**:

.. code:: console

   $ dune build @runtest-test_parser

**Running all tests**:

.. code:: console

   $ dune runtest

Test Execution
--------------

Tests are executed in the build directory (``_build/default/...``), not the
source directory. This ensures:

- Tests don't modify source files
- Tests are sandboxed from each other
- Reproducible builds

**Accessing source files**: Declare them in ``deps`` to make them available:

.. code:: dune

   (test
    (name my_test)
    (deps test_data.json))

Empty Interface Files
---------------------

Starting from Dune 2.9, empty interface files can be automatically generated
for test executables. This is controlled by the ``executables_implicit_empty_intf``
setting in ``dune-project``.

**See**: :doc:`/reference/dune-project/executables_implicit_empty_intf`

Complete Example
----------------

.. code:: dune

   (tests
    (names
     test_parser
     test_evaluator
     test_integration)
    (libraries
     mylib
     alcotest
     lwt.unix)
    (deps
     test_data.json
     (glob_files fixtures/*.txt))
    (preprocess (pps ppx_deriving.show))
    (flags (-w -27))
    (action (run %{test} --color=always)))

This defines three tests that:

- Link against mylib, alcotest, and lwt.unix
- Depend on test data files
- Use ppx_deriving.show for preprocessing
- Compile with custom warning settings
- Run with ``--color=always`` flag

See Also
--------

- :doc:`/howto/tests-stanza` - How to use the test/tests stanza
- :doc:`/howto/test-with-alcotest` - Using Alcotest with tests
- :doc:`/concepts/promotion` - Understanding expect tests and promotion
- :doc:`/explanation/testing-overview` - Overview of all test types
- :ref:`executables stanza <shared-exe-fields>` - Full field documentation
