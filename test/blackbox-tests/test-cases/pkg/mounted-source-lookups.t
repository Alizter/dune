Rules that look at the sources of the directory they are generated for must
find them when the project is mounted from a lock directory. The workspace
behaviour of each feature is covered by the test named with it.

  $ make_lockdir
  $ cat > dune-project <<'EOF'
  > (lang dune 3.25)
  > (package (name main) (depends foo))
  > EOF
  $ mkdir -p _source/docs/nested _source/stubs/inc _source/escape _source/bad
  $ cat > _source/dune-project <<'EOF'
  > (lang dune 3.25)
  > (package (name foo) (dir .))
  > EOF
  $ make_lockpkg foo <<EOF
  > (version 1.0)
  > (source (copy $PWD/_source))
  > (build (run false))
  > EOF
  $ mount=_build/default/.pkg/foo

A source tree installed by the package (install/install-source-tree.t).

  $ cat > _source/dune <<'EOF'
  > (install
  >  (section share)
  >  (source_trees docs))
  > EOF
  $ echo page > _source/docs/index.txt
  $ echo nested > _source/docs/nested/more.txt
  $ dune build $mount/foo.install 2>&1 && grep docs $mount/foo.install
    "_build/install/default/share/foo/docs/index.txt" {"docs/index.txt"}
    "_build/install/default/share/foo/docs/nested/more.txt" {"docs/nested/more.txt"}

A generated directory installed under another name, including nested files
(package-materialization/install-dirs.t and pkg-pform/install-dirs.t).

  $ cat >> _source/dune <<'EOF'
  > (rule
  >  (target (dir generated))
  >  (action
  >   (progn
  >    (run mkdir -p %{target}/sub)
  >    (system "echo top > %{target}/top.txt")
  >    (system "echo nested > %{target}/sub/nested.txt"))))
  > (install
  >  (section share)
  >  (dirs (generated as payload)))
  > EOF
  $ cat > dune <<'EOF'
  > (rule
  >  (target directory-files)
  >  (deps (package foo))
  >  (action
  >   (with-stdout-to %{target}
  >    (progn
  >     (cat %{pkg:foo:share:payload}/top.txt)
  >     (cat %{pkg:foo:share:payload}/sub/nested.txt)))))
  > EOF
  $ dune build directory-files
  $ cat _build/default/directory-files
  top
  nested

Foreign stubs with an include directory in the source.

  $ cat > _source/stubs/dune <<'EOF'
  > (library
  >  (public_name foo.stubs)
  >  (name stubs)
  >  (foreign_stubs
  >   (language c)
  >   (names stub)
  >   (include_dirs inc)))
  > EOF
  $ echo '#define VALUE 42' > _source/stubs/inc/value.h
  $ cat > _source/stubs/stub.c <<'EOF'
  > #include <caml/mlvalues.h>
  > #include "value.h"
  > value foo_value(value unit) { return Val_int(VALUE); }
  > EOF
  $ dune build $mount/stubs/stubs.cma 2>&1

Duplicate foreign-object diagnostics list every conflicting source. Workspace
paths stay relative to the workspace
(foreign-stubs/duplicate-c-cxx-obj/same-stanza.t).

  $ mkdir _source/stubs/sub
  $ cp _source/stubs/stub.c _source/stubs/sub/stub.c
  $ cat > _source/stubs/dune <<'EOF'
  > (include_subdirs unqualified)
  > (library
  >  (public_name foo.stubs)
  >  (name stubs)
  >  (foreign_stubs
  >   (language c)
  >   (names stub)
  >   (include_dirs inc)))
  > EOF
  $ (cd _source && dune build --root . stubs/stubs.cma)
  File "stubs/dune", line 7, characters 9-13:
  7 |   (names stub)
               ^^^^
  Error: Multiple sources map to the same object name "stub":
  - stubs/stub.c
  - stubs/sub/stub.c
  This is not allowed; please rename them or remove "stub" from object names.
  Hint: You can also avoid the name clash by placing the objects into different
  foreign archives and building them in different directories. Foreign archives
  can be defined using the (foreign_library ...) stanza.
  [1]

Mounted diagnostics retain the build context, so the conflicting files can be
opened from the workspace root.

  $ dune build $mount/stubs/stubs.cma
  File "_build/default/.pkg/foo/stubs/dune", line 7, characters 9-13:
  Error: Multiple sources map to the same object name "stub":
  - _build/default/.pkg/foo/stubs/stub.c
  - _build/default/.pkg/foo/stubs/sub/stub.c
  This is not allowed; please rename them or remove "stub" from object names.
  Hint: You can also avoid the name clash by placing the objects into different
  foreign archives and building them in different directories. Foreign archives
  can be defined using the (foreign_library ...) stanza.
  [1]
  $ rm _source/stubs/sub/stub.c
  $ dune build $mount/stubs/stubs.cma

An install destination that escapes the package. A workspace project gets a
deprecation warning (stanzas/install/start-install-dst-with-parent-error.t);
for a mounted package it is an error.

  $ cat > _source/escape/dune <<'EOF'
  > (install
  >  (section share)
  >  (files (data as ../escaped)))
  > EOF
  $ echo data > _source/escape/data
  $ dune build $mount/foo.install 2>&1
  File "_build/default/.pkg/foo/escape/dune", line 3, characters 17-27:
  Error: The destination path ../escaped begins with .. which is not allowed.
  Destinations in install stanzas may not begin with .. to prevent a package's
  installed files from escaping that package's install directories.
  [1]

An alias dependency on an alias that is not defined, and on a directory that
does not exist. The workspace messages name the workspace directory. The
mounted messages name a workspace directory that does not exist instead of
the mounted directory's build path.

  $ mkdir _source/aliases
  $ cat > _source/aliases/dune <<'EOF'
  > (rule
  >  (target not-defined)
  >  (deps (alias_rec nothing))
  >  (action (with-stdout-to %{target} (echo ok))))
  > (rule
  >  (target no-directory)
  >  (deps (alias_rec nowhere/default))
  >  (action (with-stdout-to %{target} (echo ok))))
  > EOF
  $ (cd _source && dune build --root . aliases/not-defined 2>&1)
  File "aliases/dune", line 3, characters 18-25:
  3 |  (deps (alias_rec nothing))
                        ^^^^^^^
  Error: This alias is empty.
  Alias "nothing" is not defined in aliases or any of its descendants.
  [1]
  $ (cd _source && dune build --root . aliases/no-directory 2>&1)
  File "aliases/dune", line 7, characters 18-33:
  7 |  (deps (alias_rec nowhere/default))
                        ^^^^^^^^^^^^^^^
  Error: Don't know about directory aliases/nowhere!
  [1]
  $ dune build $mount/aliases/not-defined 2>&1
  File "_build/default/.pkg/foo/aliases/dune", line 3, characters 18-25:
  Error: This alias is empty.
  Alias "nothing" is not defined in .pkg/foo/aliases or any of its descendants.
  [1]
  $ dune build $mount/aliases/no-directory 2>&1
  File "_build/default/.pkg/foo/aliases/dune", line 7, characters 18-33:
  Error: Don't know about directory .pkg/foo/aliases/nowhere!
  [1]

A compilation error in the package. The location is relative to the context
directory, so it does not name a file under the workspace root.

  $ cat > _source/bad/dune <<'EOF'
  > (library (name bad))
  > EOF
  $ echo 'let x : int = "not an int"' > _source/bad/bad.ml
  $ dune build $mount/bad/bad.cma 2>&1
  File ".pkg/foo/bad/bad.ml", line 1, characters 14-26:
  1 | let x : int = "not an int"
                    ^^^^^^^^^^^^
  Error: This constant has type string but an expression was expected of type
           int
  [1]
