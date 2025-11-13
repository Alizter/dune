Cram Tests
==========

Cram tests are expectation tests that describe a shell session. They contain
commands and expected outputs. When executed, the commands run and the actual
output is compared to the expected output.

.. seealso:: :doc:`/howto/cram-tests` for a practical guide with examples.

.. _cram-syntax:

Syntax
------

Cram tests are parsed line by line. Each line type is identified by its
indentation and first characters:

.. list-table::
   :header-rows: 1
   :widths: 25 20 55

   * - Prefix
     - Type
     - Description
   * - ``··$·``
     - Command
     - Shell command to execute.
   * - ``··>·``
     - Continuation
     - Continuation of the previous command.
   * - ``··``
     - Output
     - Expected output or exit code (e.g., ``[1]``).
   * - (none)
     - Comment
     - Documentation text, ignored by the test runner.

The ``·`` character represents a space. See :ref:`cram-syntax-basics` for
examples.

File and Directory Tests
------------------------

Cram tests come in two forms:

*File tests* are standalone ``.t`` files:

.. code::

   mytest.t

*Directory tests* are ``.t`` directories containing a ``run.t`` file and
optional test data:

.. code::

   mytest.t/
   ├── run.t       (required)
   └── data.txt    (test data)

See :ref:`cram-file-vs-directory` for guidance on choosing between them.

Running Cram Tests
------------------

Each cram test creates an alias from its name (``something.t`` creates
``@something``) and is added to the :doc:`@runtest </reference/aliases/runtest>`
alias. Tests are run with ``dune runtest``. See :ref:`cram-running-promoting`
for examples.

Configuration
-------------

Cram tests can be configured using the :doc:`(cram) stanza <dune/cram>`.

Execution Process
-----------------

When a Cram test runs:

1. Dune creates a temporary :doc:`sandbox </concepts/sandboxing>` directory.
2. :ref:`Declared dependencies <cram-deps-field>` are made available from
   within the sandbox.
3. Each command is executed by the shell (``sh`` by default, configurable via
   the :ref:`shell field <cram-shell-field>`).
4. Output is captured and sanitized:

   - The test directory is replaced with ``$TESTCASE_ROOT``.
   - The temporary directory is replaced with ``$TMPDIR``.
   - Custom paths can be added via ``BUILD_PATH_PREFIX_MAP``.

   See :ref:`cram-output-sanitation` for further details.

5. A corrected ``.t`` file is generated with actual output inserted after
   each command.

If the actual output differs from the expected output, Dune displays a diff:

.. code-block:: diff

   File "test.t", line 1, characters 0-0:
   diff --git a/_build/default/test.t b/_build/default/test.t.corrected
   --- a/_build/default/test.t
   +++ b/_build/default/test.t.corrected
   @@ -1,2 +1,3 @@
      $ echo hello
   -  goodbye
   +  hello

Accept the new output with ``dune promote``. See :doc:`/concepts/promotion`
for details.

If a :ref:`timeout <cram-timeout-field>` is configured and exceeded, Dune
terminates the test early. The error message indicates which command was
running and the location of the configured time limit.

If a command exits the shell early (e.g., ``exit 1``), the shell terminates
immediately. The output of that command and all subsequent commands is replaced
with ``***** UNREACHABLE *****`` in the corrected file. Output from commands
that executed before the exit can still be promoted.

If :ref:`conflict_markers <cram-conflict-markers-field>` is set to ``error``,
Dune will refuse to run tests containing unresolved conflict markers from Git,
diff3, or Jujutsu.

