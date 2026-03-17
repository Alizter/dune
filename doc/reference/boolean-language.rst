Boolean Language
================

The Boolean language allows the user to define simple Boolean expressions that
Dune can evaluate. Here's a semiformal specification of the language:

.. productionlist:: blang
   op : '=' | '<' | '>' | '<>' | '>=' | '<='
   expr : (and <expr>+)
        : (or <expr>+)
        : (<op> <template> <template>)
        : (not <expr>)
        : <template>

After an expression is evaluated, it must be exactly the string ``true`` or
``false`` to be considered as a Boolean. Any other value will be treated as an
error.

Short-Circuit Evaluation
------------------------

.. versionadded:: 3.23

The ``and`` and ``or`` operators use short-circuit evaluation:

- ``(and <expr>...)``: Expressions are evaluated left-to-right. Evaluation
  stops as soon as an expression evaluates to ``false``, and the remaining
  expressions are not evaluated.

- ``(or <expr>...)``: Expressions are evaluated left-to-right. Evaluation
  stops as soon as an expression evaluates to ``true``, and the remaining
  expressions are not evaluated.

This is useful when later expressions depend on earlier ones. For example:

.. code:: dune

   (and %{lib-available:lwt} (>= %{version:lwt} 5.0))

Here, if ``lwt`` is not available, the version check is not evaluated,
avoiding an error from trying to get the version of a non-existent library.

Example
-------

Below is a simple example of a condition expressing that the build
has a Flambda compiler, with the help of variable expansion, and is
targeting OSX:

.. code:: dune

   (and %{ocaml-config:flambda} (= %{ocaml-config:system} macosx))
