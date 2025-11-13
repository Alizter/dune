.. _testing-overview:

****************
Testing in Dune
****************

Dune streamlines the testing story so you can focus on the tests themselves
and not bother with setting up various test frameworks.

Testing Philosophy
==================

Dune's approach to testing is built around simplicity and integration. Tests
are discovered automatically, run with a single command, and integrate
seamlessly with the build system. The core testing workflow is:

1. Write tests using one of the supported approaches
2. Run tests with ``dune runtest``
3. Inspect any failures
4. Promote corrections when needed (for expectation tests)

Types of Tests
==============

Dune supports several complementary approaches to testing, each suited to
different use cases:

Inline Tests
------------

Tests written directly inside ``.ml`` files of a library using frameworks like
``ppx_inline_test``. These tests live alongside the code they test and are
ideal for unit testing individual functions and modules.

**When to use:**

- Testing internal library functions
- Unit testing pure logic
- Testing code that doesn't require complex setup
- When you want tests close to the implementation

**Learn more:** :doc:`/howto/inline-tests`

Inline Expectation Tests
-------------------------

A special case of inline tests where code prints output followed by the
expected result, using frameworks like ``ppx_expect``. The test framework
captures actual output and compares it to the expectation.

**When to use:**

- Testing functions that produce complex output (pretty-printers, formatters)
- Testing code generation or transformation
- When the expected output is large or multi-line
- When you want to review and approve output changes

**Learn more:** :doc:`/howto/expect-tests`

Custom Tests with test/tests Stanza
------------------------------------

Tests defined as standalone executables that are run as part of the test
suite. Can optionally diff their output against expected results.

**When to use:**

- Testing executable programs
- Integration testing
- Tests that require complex setup
- Tests that need specific dependencies not used by the library

**Learn more:** :doc:`/howto/tests-stanza`

Cram Tests
----------

Shell-based expectation tests written in a ``.t`` file using a syntax similar
to interactive shell sessions. Ideal for end-to-end testing of command-line
programs.

**When to use:**

- Testing command-line tools
- End-to-end testing
- Testing build behavior
- When you want to show examples of usage
- Testing integration between multiple tools

**Learn more:** :doc:`/howto/cram-tests`

Custom Test Rules
-----------------

Tests defined using low-level ``rule`` stanzas with the ``runtest`` alias.
Provides maximum flexibility for special testing needs.

**When to use:**

- Custom test frameworks not covered above
- Special build-time tests
- Performance benchmarks
- When you need full control over test execution

**Learn more:** :doc:`/howto/custom-test-rules`

Third-Party Test Frameworks
----------------------------

Dune integrates with popular OCaml test frameworks like Alcotest, QCheck, and
others. These can be used with either inline tests (via custom backends) or
the test/tests stanza.

**Learn more:**

- :doc:`/howto/test-with-alcotest`
- :doc:`/howto/custom-inline-test-backend` (for integrating other frameworks)

Running Tests
=============

Regardless of which testing approach you use, the primary way to run tests is:

.. code:: console

   $ dune runtest

This builds and runs all tests defined in the current directory and
subdirectories. Under the hood, this is shorthand for building the ``runtest``
alias:

.. code:: console

   $ dune build @runtest

You can run tests in specific locations:

.. code:: console

   $ dune runtest lib/         # Tests in lib/ and subdirectories
   $ dune runtest test/foo.t   # Single cram test
   $ dune build @lib/runtest   # Tests in lib/ only (not subdirectories)

See :doc:`/reference/aliases/runtest` for details on the runtest alias.

Expectation Testing and Promotion
==================================

Many test types in Dune use *expectation testing* (also called *snapshot
testing*). The workflow is:

1. Write a test with initial expectations (which may be empty)
2. Run the test with ``dune runtest``
3. Review the diff showing actual vs expected output
4. Accept the correction with ``dune promote`` if correct

This workflow is supported by:

- Inline expectation tests (ppx_expect)
- Cram tests
- Custom tests using the ``diff`` action
- Tests with ``.expected`` files

You can automatically promote corrections while running tests:

.. code:: console

   $ dune runtest --auto-promote

See :doc:`/concepts/promotion` for details on the promotion mechanism.

Choosing a Test Approach
=========================

Here's a decision tree to help choose the right testing approach:

**Testing a command-line tool or end-to-end behavior?**
  → Use :doc:`Cram tests </howto/cram-tests>`

**Testing library code with complex or multi-line output?**
  → Use :doc:`inline expectation tests </howto/expect-tests>`

**Testing library code with simple assertions?**
  → Use :doc:`inline tests </howto/inline-tests>`

**Testing an executable program or need integration testing?**
  → Use :doc:`test/tests stanza </howto/tests-stanza>`

**Need a specific test framework like Alcotest?**
  → See :doc:`/howto/test-with-alcotest` or other framework guides

**Need maximum control or custom test logic?**
  → Use :doc:`custom test rules </howto/custom-test-rules>`

Best Practices
==============

- **Use the right tool for the job**: Don't force inline tests for everything;
  cram tests are often better for CLI tools.

- **Keep tests fast**: Slow tests discourage running them frequently. Use
  smaller test scopes when possible.

- **Test at the right level**: Unit tests for libraries, integration tests for
  executables, cram tests for CLI behavior.

- **Review promoted changes carefully**: ``dune promote`` makes it easy to
  accept changes, but review diffs to ensure they're correct.

- **Use sandboxing**: Cram tests are automatically sandboxed. For custom tests,
  consider using sandboxing to ensure reproducibility.

- **Organize tests logically**: Group related tests in directories, use
  descriptive names.

See Also
========

- :doc:`/concepts/promotion` - Understanding diffing and promotion
- :doc:`/concepts/sandboxing` - How sandboxing ensures reproducible tests
- :doc:`/reference/aliases/runtest` - The runtest alias reference
