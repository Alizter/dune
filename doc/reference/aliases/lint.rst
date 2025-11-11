@lint
=====

This alias runs linting tools specified via the ``(lint)`` field in
:doc:`library </reference/dune/library>`, :doc:`executable
</reference/dune/executable>`, :doc:`test </reference/dune/test>`, and other
buildable stanzas.

The ``(lint)`` field uses the same syntax as the ``(preprocess)`` field (see
:doc:`/reference/preprocessing-spec`), allowing you to specify linting tools
using ``(pps ...)``, ``(action ...)``, or per-module specifications.

Linters that produce corrections will generate files with a ``.lint-corrected``
suffix. These corrections can be promoted to the source tree using ``dune
promote``.
