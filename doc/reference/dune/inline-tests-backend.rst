inline_tests.backend
--------------------

.. describe:: (inline_tests.backend ...)

   Defines a library as an inline test backend. This allows other libraries to use
   it for running inline tests.

   Backends tell Dune how to generate, build, and run test executables for
   libraries with ``inline_tests`` enabled.

   Create a backend when:

   - You're writing a test framework
   - Integrating an existing framework that needs custom runner generation
   - You want libraries to automatically use your framework with ``inline_tests``

   Well-known backends include:

   - ``ppx_inline_test`` - Jane Street's inline test framework
   - ``ppx_expect`` - Jane Street's expect test framework (extends ppx_inline_test)
   - ``qtest`` - Inline tests in comments

   Example:

   .. code:: dune

      (library
       (name my_test_framework)
       (public_name my_test_framework)
       (inline_tests.backend
        (generate_runner (run my-test-generator %{impl-files}))
        (runner_libraries (my_test_framework))))

   .. seealso:: :doc:`/howto/custom-inline-test-backend`

   .. describe:: (generate_runner <action>)

      **Required**. An action that generates OCaml code for the test runner, printed
      to stdout. This action executes in the directory of the library using the backend.

      The action follows the :doc:`/reference/actions/index` specification and must
      produce valid OCaml code that serves as the test runner's main module.

      Available variables:

      - ``%{library-name}`` - Name of the library being tested
      - ``%{impl-files}`` - Space-separated list of .ml and .re files
      - ``%{intf-files}`` - Space-separated list of .mli and .rei files

      Examples:

      .. code:: dune

         ; External generator tool
         (generate_runner (run my-generator --lib=%{library-name} %{impl-files}))

         ; Inline command
         (generate_runner
          (bash "echo 'let () = My_framework.run_all_tests ()'"))

         ; Using a binary from PATH
         (generate_runner (run %{bin:my-test-gen} %{impl-files}))

      **Note**: Avoid using ``sed`` or shell scripts for portability. Use OCaml tools
      instead.

      .. seealso:: :doc:`/reference/actions/index`

   .. describe:: (runner_libraries (<library-names>))

      Libraries to link into the test runner executable. These provide the runtime
      support for your test framework.

      Example:

      .. code:: dune

         (runner_libraries (my_test_framework base))

      If ``generate_runner`` outputs code like ``My_test_framework.run_all_tests ()``,
      then ``my_test_framework`` must be in ``runner_libraries`` so the generated
      code can reference it.

      **Default**: Empty list.

      **Note**: The library being tested is automatically available and doesn't need
      to be listed.

   .. describe:: (flags <flags>)

      Command-line arguments to pass when running the test executable.

      Uses the :doc:`/reference/ordered-set-language`.

      Available variables:

      - ``%{library-name}`` - Name of the library being tested
      - ``%{partition}`` - Partition name (if list_partitions_flags is set)
      - Standard Dune variables

      Examples:

      .. code:: dune

         (flags (-verbose -color=always))

         ; With variables
         (flags (--library=%{library-name} --partition=%{partition}))

      **Default**: No flags.

      **Note**: Flags from the backend and flags from ``(inline_tests (flags ...))``
      in the library are concatenated.

      .. seealso:: :doc:`/reference/ordered-set-language`

   .. describe:: (list_partitions_flags <flags>)

      Flags to pass when listing available test partitions for parallel execution.

      Uses the :doc:`/reference/ordered-set-language`.

      This enables parallel test execution by partitioning the test suite. When set,
      Dune:

      1. Runs the test executable with ``list_partitions_flags``
      2. Expects partition names on stdout, one per line
      3. Runs the test executable multiple times in parallel, once per partition
      4. Passes ``%{partition}`` in the ``flags`` for each run

      Example:

      .. code:: dune

         (list_partitions_flags (--list-partitions))

      Your test runner must output partition names when run with these flags:

      .. code:: console

         $ ./test_runner.exe --list-partitions
         partition_1
         partition_2
         partition_3

      And accept the partition name when run normally (via ``flags``):

      .. code:: console

         $ ./test_runner.exe --partition=partition_1
         # Runs only tests in partition_1

      **Default**: Not set (partitioning disabled).

   .. describe:: (extends (<backend-names>))

      Other backends this backend extends. Used for layering test frameworks.

      Example:

      .. code:: dune

         (library
          (name my_expect_tests)
          (inline_tests.backend
           (extends (ppx_inline_test))
           ...))

      When your framework builds on another framework (e.g., ppx_expect extends
      ppx_inline_test), specify the parent backend here.

      Behavior when extending:

      - Fields from all backends in the extension chain are concatenated
      - If backend B extends backend A, A's fields are processed before B's fields
      - The order of concatenation for other backends is unspecified

      Constraints:

      - A library can use multiple backends simultaneously
      - Exactly one backend must be a "root" (not extending another)
      - Extension chains must not have cycles

      Example chain::

         ppx_inline_test (root)
           ↑ extended by ppx_expect
             ↑ extended by my_custom_expect

      Libraries using ``my_custom_expect`` will have all three backends'
      configuration combined.

      **Default**: No backends extended (this is a root backend).

Complete Examples
~~~~~~~~~~~~~~~~~

Simple Backend
""""""""""""""

Minimal backend using a generator tool:

.. code:: dune

   (library
    (name my_test_framework)
    (public_name my_test_framework)
    (inline_tests.backend
     (generate_runner (run my-test-gen %{impl-files}))
     (runner_libraries (my_test_framework))))

Backend with Flags
""""""""""""""""""

Backend that passes runtime flags to tests:

.. code:: dune

   (library
    (name verbose_tests)
    (public_name verbose_tests)
    (inline_tests.backend
     (generate_runner (run test-gen %{impl-files}))
     (runner_libraries (verbose_tests base))
     (flags (-verbose -color=always -library=%{library-name}))))

Backend with Partitions
"""""""""""""""""""""""

Backend supporting parallel execution:

.. code:: dune

   (library
    (name parallel_tests)
    (public_name parallel_tests)
    (inline_tests.backend
     (generate_runner (run parallel-test-gen %{impl-files}))
     (runner_libraries (parallel_tests))
     (flags (--partition=%{partition}))
     (list_partitions_flags (--list-partitions))))

Extending Backend
"""""""""""""""""

Backend that extends ppx_inline_test:

.. code:: dune

   (library
    (name enhanced_inline_test)
    (public_name enhanced_inline_test)
    (inline_tests.backend
     (extends (ppx_inline_test))
     (runner_libraries (enhanced_inline_test))
     (flags (--enhanced-mode))))

Usage by Libraries
~~~~~~~~~~~~~~~~~~

Once a backend is defined, libraries can use it:

.. code:: dune

   (library
    (name mylib)
    (inline_tests (backend my_test_framework))
    (preprocess (pps my_test_framework.ppx)))

Or auto-detection (if PPX rewriter registers the backend):

.. code:: dune

   (library
    (name mylib)
    (inline_tests)
    (preprocess (pps ppx_inline_test)))  ; Backend auto-detected

Field Concatenation
~~~~~~~~~~~~~~~~~~~

When multiple backends are involved (through ``extends``), fields are
concatenated:

**generate_runner**
   All actions are run in sequence, outputs concatenated

**runner_libraries**
   All libraries are linked

**flags**
   All flags are passed to the test runner

**list_partitions_flags**
   Only the root backend's flags are used (not concatenated)

Example: If backend B extends A:

Backend A:

.. code:: dune

   (runner_libraries (framework_a))
   (flags (--framework-a))

Backend B:

.. code:: dune

   (extends (framework_a))
   (runner_libraries (framework_b))
   (flags (--framework-b))

Effective configuration:

.. code:: dune

   (runner_libraries (framework_a framework_b))
   (flags (--framework-a --framework-b))

Implementation Notes
~~~~~~~~~~~~~~~~~~~~

Generated Runner Module
"""""""""""""""""""""""

The code output by ``generate_runner`` becomes a module in the test executable.
It typically should:

1. Reference the test framework from ``runner_libraries``
2. Call a function to discover and run tests
3. Handle any flags passed via the ``flags`` field
4. Exit with code 0 on success, non-zero on failure

Typical generated runner structure:

.. code:: ocaml

   (* Generated by backend *)
   let () =
     My_framework.run_tests ()

Library Information
"""""""""""""""""""

The ``%{library-name}``, ``%{impl-files}``, and ``%{intf-files}`` variables
provide information about the library being tested:

``%{library-name}``
   String, the library's name from the dune file

``%{impl-files}``
   Space-separated list of absolute paths to .ml/.re files

``%{intf-files}``
   Space-separated list of absolute paths to .mli/.rei files

Constraints
~~~~~~~~~~~

- The ``inline_tests.backend`` field can only appear in ``library`` stanzas
- The ``generate_runner`` field is required
- Actions in ``generate_runner`` must not modify files (read-only)
- Generated code must be valid OCaml
- Backends should have a ``public_name`` so other projects can reference them

Troubleshooting
~~~~~~~~~~~~~~~

Backend Not Found
"""""""""""""""""

Error: "Backend X not found"

**Solution**: Ensure the backend library is:

1. In scope (available as a dependency)
2. Has a ``public_name``
3. Actually defines ``inline_tests.backend``

Generated Code Fails to Compile
""""""""""""""""""""""""""""""""

Error during test compilation.

**Solutions**:

1. Check that ``generate_runner`` outputs valid OCaml
2. Verify ``runner_libraries`` includes all needed libraries
3. Test the generator manually: run the action and inspect output

Tests Don't Run
"""""""""""""""

Tests are generated but don't execute.

**Solutions**:

1. Ensure generated code actually calls test framework functions
2. Check that ``flags`` are correct for your test runner
3. Verify the test framework is properly initialized in generated code

See Also
~~~~~~~~

- :doc:`/howto/custom-inline-test-backend` - How to create a backend
- :doc:`/reference/dune/inline-tests-field` - Using backends in libraries
- :doc:`/reference/actions/index` - Action syntax
- :doc:`/reference/ordered-set-language` - Flags syntax

Examples in the Wild
~~~~~~~~~~~~~~~~~~~~

Real-world backend examples:

- `ppx_inline_test <https://github.com/janestreet/ppx_inline_test>`_ - Jane
  Street's inline test framework
- `ppx_expect <https://github.com/janestreet/ppx_expect>`_ - Expect tests
  (extends ppx_inline_test)
