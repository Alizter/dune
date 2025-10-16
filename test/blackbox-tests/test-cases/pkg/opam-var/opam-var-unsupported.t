  $ . ../helpers.sh

  $ mkrepo
  > fail_solve() {
  >   mkpkg testpkg <<EOF
  > build: [ "echo" $1 ]
  > EOF
  >   solve_output=$(solve testpkg 2>&1)
  >   if [ $? -eq 0 ]; then
  >     echo "Expected solve to fail, but it succeeded" >&2
  >   else
  >     echo "$solve_output" >&2
  >   fi
  > }

opam variables that are explicitly unsupported in dune

These should all have nice error messages explaining that they are not supported.

# opam-version
  $ fail_solve opam-version
  File "$TESTCASE_ROOT/mock-opam-repository/packages/testpkg/testpkg.0.0.1/opam", line 1, characters 0-0:
  Error: Variable "opam-version" is not supported.
  -> required by _build/_private/default/.lock/dune.lock
  -> required by lock directory environment for context "default"
  -> required by base environment for context "default"
  -> required by loading findlib for context "default"
  -> required by loading the OCaml compiler for context "default"
# root
  $ fail_solve root 
  File "$TESTCASE_ROOT/mock-opam-repository/packages/testpkg/testpkg.0.0.1/opam", line 1, characters 0-0:
  Error: Variable "root" is not supported.
  -> required by _build/_private/default/.lock/dune.lock
  -> required by lock directory environment for context "default"
  -> required by base environment for context "default"
  -> required by loading findlib for context "default"
  -> required by loading the OCaml compiler for context "default"
# _:hash
  $ fail_solve _:hash
  File "$TESTCASE_ROOT/mock-opam-repository/packages/testpkg/testpkg.0.0.1/opam", line 1, characters 0-0:
  Error: Variable "hash" is not supported.
  -> required by _build/_private/default/.lock/dune.lock
  -> required by lock directory environment for context "default"
  -> required by base environment for context "default"
  -> required by loading findlib for context "default"
  -> required by loading the OCaml compiler for context "default"
# _:build-id
  $ fail_solve _:build-id
  File "$TESTCASE_ROOT/mock-opam-repository/packages/testpkg/testpkg.0.0.1/opam", line 1, characters 0-0:
  Error: Variable "build-id" is not supported.
  -> required by _build/_private/default/.lock/dune.lock
  -> required by lock directory environment for context "default"
  -> required by base environment for context "default"
  -> required by loading findlib for context "default"
  -> required by loading the OCaml compiler for context "default"
# misc
  $ fail_solve misc
  File "$TESTCASE_ROOT/mock-opam-repository/packages/testpkg/testpkg.0.0.1/opam", line 1, characters 0-0:
  Error: Variable "misc" is not supported.
  -> required by _build/_private/default/.lock/dune.lock
  -> required by lock directory environment for context "default"
  -> required by base environment for context "default"
  -> required by loading findlib for context "default"
  -> required by loading the OCaml compiler for context "default"
# _:misc
  $ fail_solve _:misc
  File "$TESTCASE_ROOT/mock-opam-repository/packages/testpkg/testpkg.0.0.1/opam", line 1, characters 0-0:
  Error: Variable "misc" is not supported.
  -> required by _build/_private/default/.lock/dune.lock
  -> required by lock directory environment for context "default"
  -> required by base environment for context "default"
  -> required by loading findlib for context "default"
  -> required by loading the OCaml compiler for context "default"
# _:depends
  $ fail_solve _:depends
  File "$TESTCASE_ROOT/mock-opam-repository/packages/testpkg/testpkg.0.0.1/opam", line 1, characters 0-0:
  Error: Variable "depends" is not supported.
  -> required by _build/_private/default/.lock/dune.lock
  -> required by lock directory environment for context "default"
  -> required by base environment for context "default"
  -> required by loading findlib for context "default"
  -> required by loading the OCaml compiler for context "default"
# _:build
  $ fail_solve _:build
  File "$TESTCASE_ROOT/mock-opam-repository/packages/testpkg/testpkg.0.0.1/opam", line 1, characters 0-0:
  Error: Variable "build" is not supported.
  -> required by _build/_private/default/.lock/dune.lock
  -> required by lock directory environment for context "default"
  -> required by base environment for context "default"
  -> required by loading findlib for context "default"
  -> required by loading the OCaml compiler for context "default"
# _:opamfile
  $ fail_solve _:opamfile
  File "$TESTCASE_ROOT/mock-opam-repository/packages/testpkg/testpkg.0.0.1/opam", line 1, characters 0-0:
  Error: Variable "opamfile" is not supported.
  -> required by _build/_private/default/.lock/dune.lock
  -> required by lock directory environment for context "default"
  -> required by base environment for context "default"
  -> required by loading findlib for context "default"
  -> required by loading the OCaml compiler for context "default"
