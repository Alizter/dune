Invalid Opam stanza package graphs are rejected before rules are generated.

  $ unset DUNE_SOURCE_ROOT DUNE_SOURCEROOT DUNE_PROJECT_ROOT
  $ mkdir a b
  $ cat >dune-project <<'EOF'
  > (lang dune 3.22)
  > (name test)
  > (using unreleased 0.1)
  > (package (name a) (dir a))
  > (package (name b) (dir b))
  > EOF
  $ cat >a/dune <<'EOF'
  > (opam
  >  (package a)
  >  (depends b))
  > EOF
  $ cat >b/dune <<'EOF'
  > (opam
  >  (package b)
  >  (depends a))
  > EOF

  $ dune build a/.opam/a/target
  File "b/dune", line 3, characters 10-11:
  3 |  (depends a))
                ^
  Error: The following opam stanzas form a dependency cycle:
     a
  -> b
  [1]

A dependency must be provided by another Opam stanza.

  $ cat >a/dune <<'EOF'
  > (opam
  >  (package a)
  >  (depends missing))
  > EOF
  $ cat >b/dune <<'EOF'
  > (opam
  >  (package b))
  > EOF
  $ dune build a/.opam/a/target
  File "a/dune", line 3, characters 10-17:
  3 |  (depends missing))
                ^^^^^^^
  Error: Package missing is not provided by an opam stanza
  [1]

There is only one opaque recipe owner for each package.

  $ cat >a/dune <<'EOF'
  > (opam (package a))
  > (opam (package a))
  > EOF
  $ dune build a/.opam/a/target
  File "a/dune", line 1, characters 0-18:
  1 | (opam (package a))
      ^^^^^^^^^^^^^^^^^^
  Error: The following both define the same directory target:
  _build/default/a/.opam/a/target
  - a/dune:1
  - a/dune:2
  [1]
