.. _howto-cram-tests:

.. TODO Checklist (from review):
.. Cross-referenced with: reference/cram.rst, reference/dune/cram.rst,
.. concepts/promotion.rst, concepts/sandboxing.rst, explanation/testing-overview.rst,
.. src/dune_rules/cram/, test/blackbox-tests/test-cases/cram/
..
.. =============================================================================
.. Diataxis Restructuring (see https://diataxis.fr/)
.. =============================================================================
..
.. This howto currently mixes tutorial/reference/explanation content.
.. Per Diataxis, a how-to guide should be:
.. - Goal-oriented: "How to accomplish X"
.. - Action-only: no teaching, no explanation, no digression
.. - Assume competence: user knows what they want
.. - Link out: reference for details, explanation for rationale
..
.. Broader documentation changes needed:
.. - [ ] Create tutorials/first-cram-test.rst (hand-holding beginner walkthrough)
.. - [ ] Move syntax details to reference/cram.rst (already exists, reduce duplication)
.. - [ ] Move "why" content to explanation/testing-overview.rst
.. - [ ] Refocus this howto as goal-oriented recipes
..
.. Restructure this file into goal-oriented sections:
.. - [ ] "How to test a CLI tool" (deps, basic test structure)
.. - [ ] "How to handle non-deterministic output" (sanitization, sed pipes)
.. - [ ] "How to test with fixtures" (directory tests, file creation)
.. - [ ] "How to run specific tests" (@foo alias, path targeting)
.. - [ ] "How to debug failing tests" (promotion workflow, reviewing diffs)
..
.. Remove from howto (belongs in reference):
.. - [ ] Syntax table (link to reference/cram.rst instead)
.. - [ ] Stanza field documentation (link to reference/dune/cram.rst)
.. - [ ] Exhaustive configuration options
..
.. Remove from howto (belongs in explanation):
.. - [ ] "What is a cram test" intro
.. - [ ] Design rationale for promotion
.. - [ ] Sandboxing explanation (link to concepts/sandboxing.rst)
..
.. =============================================================================
.. Corrections (from implementation review)
.. =============================================================================
.. - [ ] applies_to matches name WITHOUT .t suffix (e.g., (applies_to foo) matches foo.t)
.. - [ ] Multiple stanzas with timeout: lowest timeout wins
.. - [ ] Conflict markers require complete sequence (start + divider + end)
..
.. =============================================================================
.. Missing behaviors to document somewhere (reference or howto as appropriate)
.. =============================================================================
.. - [ ] :whole_subtree for recursive applies_to
.. - [ ] runtest_alias false to exclude from @runtest
.. - [ ] Partial promotion works (commands before early exit)
.. - [ ] LC_ALL=C set for stable output
.. - [ ] ANSI codes stripped from output
.. - [ ] Environment persists across $ commands
.. - [ ] Directory tests cannot contain dune files
.. - [ ] Empty .t directories silently skipped
..
.. =============================================================================
.. Other
.. =============================================================================
.. - [ ] Replace hypothetical mytool examples with real dune examples
.. - [ ] Verify /reference/cram link works

****************
Using Cram Tests
****************

Cram tests are shell-based expectation tests ideal for testing command-line
tools and end-to-end behavior. They're written in files with a ``.t``
extension using a syntax that resembles interactive shell sessions.

For complete syntax and configuration details, see :doc:`/reference/cram` and
:doc:`/reference/dune/cram`.

.. _cram-syntax-basics:

Writing Cram Tests
==================

Cram tests look like shell sessions. Here's a simple example (``hello.t``):

.. code:: cram

   Testing the echo command:
     $ echo "Hello, world!"
     Hello, world!

Syntax Elements
---------------

- **Commands**: Lines starting with ``␣␣$␣`` (two spaces, dollar sign, space)
- **Continuation**: Lines starting with ``␣␣>␣`` continue the previous command
- **Output**: Lines indented with two spaces show expected output
- **Exit codes**: ``[N]`` on its own line indicates the expected exit code
- **Comments**: Non-indented lines document the test

Example with continuation and exit code:

.. code:: cram

   Multi-line command using heredoc:
     $ cat <<EOF
     > line one
     > line two
     > EOF
     line one
     line two

   Command that fails:
     $ exit 1
     [1]

For the complete syntax specification, see :ref:`cram-syntax`.

File and Directory Tests
========================

Cram tests come in two forms.

File Tests
----------

A single ``.t`` file containing commands and expected output:

.. code::

   hello.t

Directory Tests
---------------

A ``.t`` directory containing a ``run.t`` script and test data:

.. code::

   mytest.t/
   ├── run.t       (required - the test script)
   ├── data.txt    (test data)
   └── fixtures/   (more test data)

.. _cram-file-vs-directory:

Choosing Between Them
---------------------

Use **file tests** when the test is self-contained. Create any needed files
using heredocs (see :ref:`cram-creating-artifacts`).

Use **directory tests** when:

- You have binary test data
- You have many test files
- You want editor tooling (syntax highlighting) for test data

Note: You cannot put ``dune`` files inside a ``.t`` directory.

.. _cram-running-promoting:

Running Tests
=============

Run all tests:

.. code:: console

   $ dune runtest

Run a specific test:

.. code:: console

   $ dune runtest path/to/test.t

Each test ``foo.t`` also gets its own ``@foo`` alias:

.. code:: console

   $ dune build @foo

The Promotion Workflow
----------------------

When you first write a test without expected output, or when output changes,
Dune shows a diff:

.. code-block:: diff

   File "hello.t", line 1, characters 0-0:
   --- a/_build/default/hello.t
   +++ b/_build/default/hello.t.corrected
   @@ -1,2 +1,3 @@
    Testing echo:
      $ echo "Hello"
   +  Hello

Review the diff, then accept it:

.. code:: console

   $ dune promote

Or combine running and promoting:

.. code:: console

   $ dune runtest --auto-promote

See :doc:`/concepts/promotion` for more on the promotion workflow.

Testing OCaml Executables
=========================

To test an executable defined in your Dune project, declare it as a dependency.

``dune`` file:

.. code:: dune

   (executable
    (name myprogram)
    (public_name myprogram))

   (cram
    (deps %{bin:myprogram}))

Your cram test can now use the program:

``test.t``:

.. code:: cram

   Test myprogram:
     $ myprogram hello
     Hello from myprogram!

The ``%{bin:myprogram}`` dependency ensures the executable is built before the
test runs.

.. CR-soon Alizter: Review sandboxing section

Sandboxing
==========

All cram tests run in a sandbox - a fresh, isolated environment for each test.
This ensures:

- Tests don't interfere with each other
- Tests are reproducible
- The source tree isn't modified

Declaring Dependencies
----------------------

Because of sandboxing, you must explicitly declare any files your test needs:

.. code:: dune

   (cram
    (deps
     config.json
     (glob_files test_data/*.txt)
     %{bin:myprogram}))

Without declaring dependencies, files won't be available in the sandbox.

See :doc:`/concepts/sandboxing` for more details on the sandboxing mechanism.

.. CR-soon Alizter: Review output sanitation section

.. _cram-output-sanitation:

Output Sanitation
=================

Cram tests often produce non-portable or non-deterministic output (timestamps,
paths, etc.). Dune automatically sanitizes some paths, and you can sanitize
other output using shell pipes.

Automatic Path Sanitation
--------------------------

Dune automatically replaces:

- Test working directory → ``$TESTCASE_ROOT``
- Temporary directory → ``$TMPDIR``

Your tests see stable variable names instead of real paths:

.. code:: cram

   Print the working directory:
     $ pwd
     $TESTCASE_ROOT

Manual Sanitation with Pipes
-----------------------------

For other non-deterministic output, use tools like ``sed``:

.. code:: cram

   Replace version-specific output with a placeholder:
     $ ocamlc -config | grep "cmi_magic_number:" | sed 's/Caml.*/$MAGIC/'
     cmi_magic_number: $MAGIC

.. CR-soon Alizter: Verify BUILD_PATH_PREFIX_MAP example works correctly

Custom Path Sanitation
-----------------------

Add custom path replacements via the ``BUILD_PATH_PREFIX_MAP`` environment
variable:

.. code:: cram

   Register $HOME for path replacement:
     $ export BUILD_PATH_PREFIX_MAP="HOME=$HOME:$BUILD_PATH_PREFIX_MAP"
     $ echo $HOME
     $HOME

Note: Dune's cram implementation does not support regex or glob matchers in
expected output (unlike the original Cram). This is intentional - such matchers
break the test/diff/promote cycle by requiring manual inspection. Use output
sanitization with pipes instead.

.. CR-soon Alizter: Review creating test artifacts section

.. _cram-creating-artifacts:

Creating Test Artifacts
========================

Use shell features to create test files:

Here Documents
--------------

.. code:: cram

   Create a JSON file using a heredoc:
     $ cat >config.json <<EOF
     > {
     >   "name": "test",
     >   "version": 1
     > }
     > EOF

     $ cat config.json
     {
       "name": "test",
       "version": 1
     }

Echo Redirection
----------------

.. code:: cram

   Create a file using echo:
     $ echo "test data" > input.txt
     $ cat input.txt
     test data

.. CR-soon Alizter: Replace hypothetical mytool examples with real dune examples

Practical Examples
==================

Testing a Command-line Tool
----------------------------

``mytool.t``:

.. code:: cram

   Basic usage:
     $ mytool --version
     mytool version 1.0.0

   Help output:
     $ mytool --help
     Usage: mytool [OPTIONS] FILE

     Options:
       --verbose    Enable verbose output
       --help       Show this help

   Processing a file:
     $ echo "input data" > test.txt
     $ mytool test.txt
     Processed: input data

Testing Error Handling
----------------------

.. code:: cram

   Invalid arguments:
     $ mytool --invalid-flag
     Error: Unknown flag --invalid-flag
     [1]

   Missing file:
     $ mytool nonexistent.txt
     Error: File not found: nonexistent.txt
     [1]

Testing Pipeline Integration
-----------------------------

.. code:: cram

   Tool pipeline:
     $ echo "data" | tool1 | tool2 | tool3
     final result

   With intermediate checks:
     $ echo "data" > input
     $ tool1 input > stage1
     $ tool2 stage1 > stage2
     $ cat stage2
     expected output

.. CR-soon Alizter: Expand best practices with more concrete guidance

Best Practices
==============

Write Self-Documenting Tests
-----------------------------

Use comments to explain what you're testing:

.. code:: cram

   Test that the program handles UTF-8 correctly:
     $ mytool --input=utf8.txt
     Processed 100 characters

One Concept Per Test File
--------------------------

Keep test files focused on one feature or scenario. Use multiple ``.t`` files
rather than one giant test file.

Review Promoted Changes
------------------------

Before running ``dune promote``, carefully review the diff to ensure changes
are intentional and correct.

Use Directory Tests for Complex Setups
---------------------------------------

If you're using ``cat <<EOF`` extensively to create test files, consider
switching to a directory test where files are real artifacts.

Test Both Success and Failure
------------------------------

Don't just test the happy path. Test error cases, invalid input, and edge
conditions.

.. CR-soon Alizter: Add guidance on naming conventions and test organization patterns

Organizing Cram Tests
=====================

Typical organization:

.. code::

   myproject/
     src/
       dune
       mylib.ml
     bin/
       dune
       main.ml
     test/
       cram/
         basic.t
         errors.t
         integration.t
         complex_scenario.t/
           run.t
           test_data.txt
           fixtures/

.. CR-soon Alizter: Review advanced configuration section

Advanced Configuration
======================

The ``(cram)`` stanza supports various configuration options. See
:doc:`/reference/dune/cram` for complete details.

Common options:

.. code:: dune

   (cram
    (deps %{bin:myprogram} (glob_files test_data/*))
    (alias integration)     ; Use different alias than default 'runtest'
    (applies_to example)    ; Only run example.t from this directory
    (enabled_if (= %{system} linux)))  ; Conditional execution

Use ``(shell bash)`` if your tests require bash-specific syntax (arrays,
``[[ ]]`` tests, etc.). The default shell is ``sh``.

Setting Timeouts
----------------

Long-running or hanging tests can block your test suite. Use the ``timeout``
field to set a time limit:

.. code:: dune

   (cram
    (timeout 10)
    (deps %{bin:myprogram}))

If the timeout is exceeded, Dune terminates the test and reports which command
was running when time ran out. This helps identify infinite loops or commands
waiting for input that never arrives.

.. note::

   The ``timeout`` field was added in Dune 3.20.

Detecting Conflict Markers
--------------------------

When working with version control, you might accidentally commit unresolved
merge conflicts into your test files. Set ``conflict_markers`` to ``error`` to
catch these:

.. code:: dune

   (cram
    (conflict_markers error))

With this setting, Dune refuses to run tests containing conflict markers from
Git, diff3, or Jujutsu, displaying an error instead. The default behavior is
to ignore conflict markers.

.. note::

   The ``conflict_markers`` field was added in Dune 3.21.

Early Shell Exits
-----------------

If a command exits the shell early (e.g., using ``exit``), the shell
terminates immediately. Dune marks the output of that command and all
subsequent commands with ``***** UNREACHABLE *****``:

.. code:: cram

   Commands after an early exit are unreachable:
     $ exit 1
     ***** UNREACHABLE *****
     $ echo "this won't run"
     ***** UNREACHABLE *****

Output from commands that did execute can still be promoted normally.

Enabling Cram Tests (Dune < 3.0)
--------------------------------

Cram tests are automatically enabled in Dune 3.0+. For older versions, enable
them in your ``dune-project`` file:

.. code:: dune

   (lang dune 2.7)
   (cram enable)

.. CR-soon Alizter: Review see also links once other docs are finalized

See Also
========

- :doc:`/reference/cram` - Complete cram syntax reference
- :doc:`/reference/dune/cram` - Cram stanza configuration reference
- :doc:`/concepts/sandboxing` - Understanding sandboxing
- :doc:`/concepts/promotion` - Understanding promotion
- :doc:`/explanation/testing-overview` - Overview of all test types

.. _Cram: https://bitheap.org/cram/
