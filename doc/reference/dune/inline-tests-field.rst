inline_tests
------------

.. describe:: (inline_tests)

   Enables inline testing for a library. Inline tests are tests written directly
   in ``.ml`` files using test frameworks like ppx_inline_test_ or ppx_expect_.

   When ``inline_tests`` is enabled, Dune generates a test executable from the
   library's source files and runs it as part of ``dune runtest``.

   Simple form (uses default backend):

   .. code:: dune

      (library
       (name mylib)
       (inline_tests)
       (preprocess (pps ppx_inline_test)))

   Extended form (with options):

   .. code:: dune

      (library
       (name mylib)
       (inline_tests
        (<field> <value>)
        ...))

   .. seealso:: :doc:`/howto/inline-tests`

   .. describe:: (backend <library-name>)

      Specifies which inline test backend to use. The backend determines how test
      runners are generated and executed.

      The backend name is the ``public_name`` of the backend library.

      **Default**: Auto-detected from preprocessing directives. If you use
      ``ppx_inline_test`` or ``ppx_expect`` in your ``preprocess`` field, the
      corresponding backend is used automatically.

      **When to specify**: Only needed for backends that don't auto-register, like
      qtest_.

      Example:

      .. code:: dune

         (library
          (name mylib)
          (inline_tests (backend qtest.lib)))

      .. seealso:: :doc:`/howto/custom-inline-test-backend`

   .. describe:: (modes <mode> ...)

      Specifies which compilation modes to run tests in.

      Available modes:

      - ``byte`` - Run tests compiled to bytecode
      - ``native`` - Run tests compiled to native code
      - ``best`` - Run native with fallback to bytecode if native unavailable
      - ``js`` - Run tests compiled to JavaScript (requires js_of_ocaml)
      - ``wasm`` - Run tests compiled to WebAssembly (requires wasm_of_ocaml)

      **Default**: ``best`` (native with bytecode fallback)

      Example:

      .. code:: dune

         (library
          (name mylib)
          (inline_tests (modes byte native js)))

      This runs the same tests three times: in bytecode, native code, and JavaScript.

      **Use case**: Ensuring cross-platform behavior, testing JavaScript-specific
      compilation, or debugging bytecode vs native issues.

   .. describe:: (deps <dep-spec> ...)

      Declares dependencies required by the tests. These files/targets must be
      available when the test runner executes.

      Example:

      .. code:: dune

         (library
          (name mylib)
          (inline_tests
           (deps
            test_data.json
            (glob_files fixtures/*.txt)
            (alias test-setup))))

      Common use cases include test data files, configuration files, generated
      fixtures, and other build targets needed by tests.

      **Default**: No additional dependencies beyond the library itself.

      .. seealso:: :doc:`/concepts/dependency-spec`

   .. describe:: (flags <flags> ...)

      Command-line arguments passed to the test runner executable when it runs.

      Example:

      .. code:: dune

         (library
          (name mylib)
          (inline_tests
           (flags (-verbose -seed 42))))

      Available variables:

      - ``%{library-name}`` - Name of the library
      - ``%{partition}`` - Partition name (if backend supports partitions)
      - Standard Dune variables

      Example with variables:

      .. code:: dune

         (library
          (name mylib)
          (inline_tests
           (flags (--library=%{library-name} --partition=%{partition}))))

      **Default**: Backend-specific defaults (see backend documentation).

      .. seealso:: :doc:`/reference/ordered-set-language`

   .. describe:: (libraries <library> ...)

      Additional libraries to link into the test runner executable.

      Example:

      .. code:: dune

         (library
          (name mylib)
          (inline_tests
           (libraries test_helpers alcotest)))

      Use this when tests need libraries that the main library doesn't depend on,
      such as test utility libraries, test frameworks (when using qtest_ or similar),
      or mock/fixture libraries.

      **Default**: Only the library being tested and the backend's
      ``runner_libraries`` are linked.

      **Note**: The library being tested is always available to tests without being
      listed.

   .. describe:: (executable (<field> <value>) ...)

      Customizes compilation of the test executable. Accepts a subset of fields from
      the ``executable`` stanza.

      Supported fields:

      - ``flags`` - Compiler flags for building the test executable
      - ``link_flags`` - Linker flags

      Example:

      .. code:: dune

         (library
          (name mylib)
          (inline_tests
           (executable
            (flags (-w -27))
            (link_flags -linkall -cclib -lm))))

      **Compiler flags**: Flags passed to the OCaml compiler when building the test
      runner. Common use cases include disabling specific warnings in test code,
      enabling debugging symbols, or setting compiler options different from the
      library.

      **Link flags**: Flags passed to the linker when building the test runner.

      **Important**: Keep ``-linkall`` in link flags unless you know what you're doing.
      It forces the linker to include your test modules, which the test runner doesn't
      explicitly depend on.

      The ``link_flags`` field supports ``(:include ...)`` forms for dynamic
      configuration.

      **Default**: ``-linkall``

Complete Example
~~~~~~~~~~~~~~~~

Here's a comprehensive example using multiple fields:

.. code:: dune

   (library
    (name mylib)
    (inline_tests
     (backend ppx_inline_test)
     (modes native js)
     (deps
      test_data.json
      (glob_files fixtures/*.txt))
     (flags (-verbose -color=always))
     (libraries test_helpers lwt)
     (executable
      (flags (-w -27))
      (link_flags -linkall -cclib -lm)))
    (preprocess (pps ppx_inline_test))
    (libraries lwt base))

This configuration:

- Uses ppx_inline_test backend
- Runs tests in both native and JavaScript
- Depends on test data files
- Passes verbose and color flags to the runner
- Links additional test libraries
- Customizes compiler and linker flags

Dependencies
~~~~~~~~~~~~

If your library uses ``ppx_inline_test``, your package must have an
unconditional dependency on it in the opam file:

.. code:: opam

   depends: [
     "ppx_inline_test"
   ]

**Do not** use ``{with-test}`` for PPX rewriters used with inline tests,
as the library needs the PPX at all times.

Interaction with Other Fields
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The ``inline_tests`` field works with the ``preprocess`` field to enable test
frameworks:

.. code:: dune

   (library
    (name mylib)
    (inline_tests)
    (preprocess (pps ppx_inline_test ppx_expect)))

This enables both ppx_inline_test_ (for ``let%test``) and ppx_expect_ (for
``let%expect_test``).

Libraries listed in the library's ``libraries`` field are automatically
available to tests. The ``libraries`` field in ``inline_tests`` adds
*additional* libraries only needed for testing:

.. code:: dune

   (library
    (name mylib)
    (libraries base stdio)        ; Available to both library and tests
    (inline_tests
     (libraries alcotest)))        ; Only available to tests

Generated Aliases
~~~~~~~~~~~~~~~~~

When ``inline_tests`` is enabled, Dune automatically creates:

1. ``@runtest`` - The standard test alias
2. ``@runtest-<library-name>`` - A library-specific test alias

Run library-specific tests:

.. code:: console

   $ dune build @runtest-mylib

This is useful for running tests for a single library in a multi-library
project.

Constraints
~~~~~~~~~~~

- The ``inline_tests`` field can only appear in ``library`` stanzas, not
  ``executable`` stanzas
- At least one PPX rewriter or backend must be specified (either via
  ``preprocess`` or the ``backend`` field)
- Cannot be used with ``wrapped false`` libraries (limitation may be lifted in
  future versions)

See Also
~~~~~~~~

- :doc:`/howto/inline-tests` - How to use inline tests
- :doc:`/howto/expect-tests` - How to use inline expectation tests
- :doc:`/howto/custom-inline-test-backend` - Creating custom backends
- :doc:`/reference/dune/inline-tests-backend` - Backend field reference
- :doc:`/reference/dune/library` - Full library stanza reference

.. _ppx_inline_test: https://github.com/janestreet/ppx_inline_test
.. _ppx_expect:      https://github.com/janestreet/ppx_expect
.. _qtest:           https://github.com/vincent-hugot/qtest
