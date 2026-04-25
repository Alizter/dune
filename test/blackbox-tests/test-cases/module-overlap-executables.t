Two executables in the same directory without explicit (modules) should error
in lang dune 3.24:

  $ cat > dune-project <<EOF
  > (lang dune 3.24)
  > EOF

  $ cat > dune <<EOF
  > (executable (name foo))
  > (executable (name bar))
  > EOF

  $ touch foo.ml bar.ml

  $ dune build @check 2>&1
  File "dune", line 1, characters 0-0:
  Error: Module "Foo" is used in several stanzas:
  - dune:1
  - dune:2
  To fix this error, you must specify an explicit "modules" field in every
  library, executable, and executables stanzas in this dune file. Note that
  each module cannot appear in more than one "modules" field - it must belong
  to a single library or executable.
  [1]

Two executables in the same directory without explicit (modules) should warn
in lang dune 3.23:

  $ cat > dune-project <<EOF
  > (lang dune 3.23)
  > EOF

  $ dune clean
  $ dune build @check 2>&1
  File "dune", line 1, characters 0-23:
  1 | (executable (name foo))
      ^^^^^^^^^^^^^^^^^^^^^^^
  Warning: Module "Foo" is used in several stanzas:
  - dune:1
  - dune:2
  To fix this error, you must specify an explicit "modules" field in every
  library, executable, and executables stanzas in this dune file. Note that
  each module cannot appear in more than one "modules" field - it must belong
  to a single library or executable.
  File "dune", line 1, characters 0-23:
  1 | (executable (name foo))
      ^^^^^^^^^^^^^^^^^^^^^^^
  Warning: Module "Bar" is used in several stanzas:
  - dune:1
  - dune:2
  To fix this error, you must specify an explicit "modules" field in every
  library, executable, and executables stanzas in this dune file. Note that
  each module cannot appear in more than one "modules" field - it must belong
  to a single library or executable.
  File "dune", line 1, characters 0-23:
  1 | (executable (name foo))
      ^^^^^^^^^^^^^^^^^^^^^^^
  Warning: Module "Foo" is used in several stanzas:
  - dune:1
  - dune:2
  To fix this error, you must specify an explicit "modules" field in every
  library, executable, and executables stanzas in this dune file. Note that
  each module cannot appear in more than one "modules" field - it must belong
  to a single library or executable.
  File "dune", line 1, characters 0-23:
  1 | (executable (name foo))
      ^^^^^^^^^^^^^^^^^^^^^^^
  Warning: Module "Bar" is used in several stanzas:
  - dune:1
  - dune:2
  To fix this error, you must specify an explicit "modules" field in every
  library, executable, and executables stanzas in this dune file. Note that
  each module cannot appear in more than one "modules" field - it must belong
  to a single library or executable.
  File "bar.ml", line 1:
  Error: Could not find the .cmi file for interface bar.mli.
  File "foo.ml", line 1:
  Error: Could not find the .cmi file for interface foo.mli.
  [1]

Two executables with explicit (modules) partitioning should succeed:

  $ cat > dune-project <<EOF
  > (lang dune 3.24)
  > EOF

  $ cat > dune <<EOF
  > (executable
  >  (name foo)
  >  (modules foo))
  > (executable
  >  (name bar)
  >  (modules bar))
  > EOF

  $ dune clean
  $ dune build @check 2>&1

Two test stanzas without explicit (modules) should error in 3.24:

  $ cat > dune <<EOF
  > (test (name foo))
  > (test (name bar))
  > EOF

  $ dune clean
  $ dune build @check 2>&1
  File "dune", line 1, characters 0-0:
  Error: Module "Foo" is used in several stanzas:
  - dune:1
  - dune:2
  To fix this error, you must specify an explicit "modules" field in every
  library, executable, and executables stanzas in this dune file. Note that
  each module cannot appear in more than one "modules" field - it must belong
  to a single library or executable.
  [1]

Executable and test overlapping should error in 3.24:

  $ cat > dune <<EOF
  > (executable (name foo))
  > (test (name bar))
  > EOF

  $ dune clean
  $ dune build @check 2>&1
  File "dune", line 1, characters 0-0:
  Error: Module "Foo" is used in several stanzas:
  - dune:1
  - dune:2
  To fix this error, you must specify an explicit "modules" field in every
  library, executable, and executables stanzas in this dune file. Note that
  each module cannot appear in more than one "modules" field - it must belong
  to a single library or executable.
  [1]

One executable disabled via enabled_if should succeed:

  $ cat > dune <<EOF
  > (executable (name foo))
  > (executable
  >  (name bar)
  >  (enabled_if false))
  > EOF

  $ dune clean
  $ dune build foo.exe 2>&1
