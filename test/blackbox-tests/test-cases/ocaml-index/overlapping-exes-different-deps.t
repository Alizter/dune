Test for https://github.com/ocaml/dune/issues/13566
@ocaml-index fails when multiple executables have different library
dependencies but share modules due to missing (modules) field.

  $ mkdir bin
  $ ln -s $(which ocaml_index) bin/ocaml-index
  $ export PATH=bin:$PATH

  $ cat > dune-project <<EOF
  > (lang dune 3.22)
  > EOF

Create two local libraries with different modules:
  $ mkdir lib_a lib_b

  $ cat > lib_a/dune <<EOF
  > (library (name lib_a))
  > EOF

  $ cat > lib_a/lib_a.ml <<EOF
  > let value_a = "from lib_a"
  > EOF

  $ cat > lib_b/dune <<EOF
  > (library (name lib_b))
  > EOF

  $ cat > lib_b/lib_b.ml <<EOF
  > let value_b = "from lib_b"
  > EOF

Two executables with different library dependencies:
  $ cat > dune <<EOF
  > (executable
  >  (name foo)
  >  (libraries lib_a))
  > (executable
  >  (name bar)
  >  (libraries lib_b))
  > EOF

  $ cat > foo.ml <<EOF
  > let () = print_endline Lib_a.value_a
  > EOF

  $ cat > bar.ml <<EOF
  > let () = print_endline Lib_b.value_b
  > EOF

shared.ml uses Lib_a, which foo has but bar doesn't:
  $ cat > shared.ml <<EOF
  > let x = Lib_a.value_a
  > EOF

Normal build succeeds because each executable only links what it needs:
  $ dune build ./foo.exe ./bar.exe
  File "dune", lines 1-3, characters 0-43:
  1 | (executable
  2 |  (name foo)
  3 |  (libraries lib_a))
  Warning: Module "Shared" is used in several stanzas:
  - dune:1
  - dune:4
  To fix this error, you must specify an explicit "modules" field in every
  library, executable, and executables stanzas in this dune file. Note that
  each module cannot appear in more than one "modules" field - it must belong
  to a single library or executable.
  File "dune", lines 1-3, characters 0-43:
  1 | (executable
  2 |  (name foo)
  3 |  (libraries lib_a))
  Warning: Module "Foo" is used in several stanzas:
  - dune:1
  - dune:4
  To fix this error, you must specify an explicit "modules" field in every
  library, executable, and executables stanzas in this dune file. Note that
  each module cannot appear in more than one "modules" field - it must belong
  to a single library or executable.
  File "dune", lines 1-3, characters 0-43:
  1 | (executable
  2 |  (name foo)
  3 |  (libraries lib_a))
  Warning: Module "Bar" is used in several stanzas:
  - dune:1
  - dune:4
  To fix this error, you must specify an explicit "modules" field in every
  library, executable, and executables stanzas in this dune file. Note that
  each module cannot appear in more than one "modules" field - it must belong
  to a single library or executable.
  File "dune", lines 1-3, characters 0-43:
  1 | (executable
  2 |  (name foo)
  3 |  (libraries lib_a))
  Warning: Module "Shared" is used in several stanzas:
  - dune:1
  - dune:4
  To fix this error, you must specify an explicit "modules" field in every
  library, executable, and executables stanzas in this dune file. Note that
  each module cannot appear in more than one "modules" field - it must belong
  to a single library or executable.
  File "dune", lines 1-3, characters 0-43:
  1 | (executable
  2 |  (name foo)
  3 |  (libraries lib_a))
  Warning: Module "Foo" is used in several stanzas:
  - dune:1
  - dune:4
  To fix this error, you must specify an explicit "modules" field in every
  library, executable, and executables stanzas in this dune file. Note that
  each module cannot appear in more than one "modules" field - it must belong
  to a single library or executable.
  File "dune", lines 1-3, characters 0-43:
  1 | (executable
  2 |  (name foo)
  3 |  (libraries lib_a))
  Warning: Module "Bar" is used in several stanzas:
  - dune:1
  - dune:4
  To fix this error, you must specify an explicit "modules" field in every
  library, executable, and executables stanzas in this dune file. Note that
  each module cannot appear in more than one "modules" field - it must belong
  to a single library or executable.

But ocaml-index fails because bar's compilation context includes shared.ml
which depends on Lib_a, but bar doesn't have lib_a as a dependency:
  $ dune build @ocaml-index
  File "dune", lines 1-3, characters 0-43:
  1 | (executable
  2 |  (name foo)
  3 |  (libraries lib_a))
  Warning: Module "Shared" is used in several stanzas:
  - dune:1
  - dune:4
  To fix this error, you must specify an explicit "modules" field in every
  library, executable, and executables stanzas in this dune file. Note that
  each module cannot appear in more than one "modules" field - it must belong
  to a single library or executable.
  File "dune", lines 1-3, characters 0-43:
  1 | (executable
  2 |  (name foo)
  3 |  (libraries lib_a))
  Warning: Module "Foo" is used in several stanzas:
  - dune:1
  - dune:4
  To fix this error, you must specify an explicit "modules" field in every
  library, executable, and executables stanzas in this dune file. Note that
  each module cannot appear in more than one "modules" field - it must belong
  to a single library or executable.
  File "dune", lines 1-3, characters 0-43:
  1 | (executable
  2 |  (name foo)
  3 |  (libraries lib_a))
  Warning: Module "Bar" is used in several stanzas:
  - dune:1
  - dune:4
  To fix this error, you must specify an explicit "modules" field in every
  library, executable, and executables stanzas in this dune file. Note that
  each module cannot appear in more than one "modules" field - it must belong
  to a single library or executable.
  File "dune", lines 1-3, characters 0-43:
  1 | (executable
  2 |  (name foo)
  3 |  (libraries lib_a))
  Warning: Module "Shared" is used in several stanzas:
  - dune:1
  - dune:4
  To fix this error, you must specify an explicit "modules" field in every
  library, executable, and executables stanzas in this dune file. Note that
  each module cannot appear in more than one "modules" field - it must belong
  to a single library or executable.
  File "dune", lines 1-3, characters 0-43:
  1 | (executable
  2 |  (name foo)
  3 |  (libraries lib_a))
  Warning: Module "Foo" is used in several stanzas:
  - dune:1
  - dune:4
  To fix this error, you must specify an explicit "modules" field in every
  library, executable, and executables stanzas in this dune file. Note that
  each module cannot appear in more than one "modules" field - it must belong
  to a single library or executable.
  File "dune", lines 1-3, characters 0-43:
  1 | (executable
  2 |  (name foo)
  3 |  (libraries lib_a))
  Warning: Module "Bar" is used in several stanzas:
  - dune:1
  - dune:4
  To fix this error, you must specify an explicit "modules" field in every
  library, executable, and executables stanzas in this dune file. Note that
  each module cannot appear in more than one "modules" field - it must belong
  to a single library or executable.
  File "bar.ml", line 1, characters 23-28:
  1 | let () = print_endline Lib_b.value_b
                             ^^^^^
  Error: Unbound module Lib_b
  File "foo.ml", line 1, characters 23-28:
  1 | let () = print_endline Lib_a.value_a
                             ^^^^^
  Error: Unbound module Lib_a
  File "shared.ml", line 1, characters 8-13:
  1 | let x = Lib_a.value_a
              ^^^^^
  Error: Unbound module Lib_a
  [1]
