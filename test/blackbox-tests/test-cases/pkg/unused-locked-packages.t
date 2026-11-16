Locked packages that nothing asks for should be neither fetched nor loaded, so
that they cannot fail an unrelated build. Currently every locked package is
fetched and loaded, and failures are remembered rather than reported.

  $ make_lockdir
  $ cat > dune-project <<'EOF'
  > (lang dune 3.25)
  > (package (name use-unfetchable) (dir use-unfetchable) (allow_empty)
  >  (depends unfetchable))
  > (package (name use-broken) (dir use-broken) (allow_empty)
  >  (depends broken))
  > EOF
  $ echo '(rule (with-stdout-to x (echo built)))' > dune

A package that builds, one whose source does not exist, and one whose Dune
project does not load.

  $ mkdir _good _broken
  $ cat > _good/dune-project <<'EOF'
  > (lang dune 3.25)
  > (package (name good))
  > EOF
  $ echo '(library (public_name good))' > _good/dune
  $ make_lockpkg good <<EOF
  > (version 1.0)
  > (source (copy $PWD/_good))
  > (build (run false))
  > EOF
  $ make_lockpkg unfetchable <<EOF
  > (version 1.0)
  > (source (copy $PWD/_absent))
  > (build (run false))
  > EOF
  $ cat > _broken/dune-project <<'EOF'
  > (lang dune 3.25)
  > (package (name broken))
  > EOF
  $ echo '(library (public_name broken) (unknown_field))' > _broken/dune
  $ make_lockpkg broken <<EOF
  > (version 1.0)
  > (source (copy $PWD/_broken))
  > (build (run false))
  > EOF

The unrelated target builds, but the two packages that can be fetched were
fetched, and an empty line is printed.

  $ dune build ./x 2>&1 | dune_cmd subst "$PWD" PWD
  
  $ cat _build/default/x
  built
  $ find _build/_fetch -name dune-project 2>/dev/null | wc -l
  2

Asking for the unfetchable package fails. The error should say what asked for
the package; currently there is no "required by" chain.

  $ mkdir use-unfetchable use-broken
  $ cat > use-unfetchable/dune <<'EOF'
  > (rule
  >  (alias demand)
  >  (deps (package unfetchable))
  >  (action (echo unreachable)))
  > EOF
  $ dune build @use-unfetchable/demand 2>&1 | dune_cmd subst "$PWD" PWD \
  > | dune_cmd delete ' *\^\^*$' | sed 's/characters [0-9-]*/characters X/'
  File "_build/_private/default/.lock/dune.lock/unfetchable.pkg", line 2, characters X:
  2 | (source (copy PWD/_absent))
  Error:
  PWD/_absent
  does not exist
  [1]

So does asking for a library of the broken package, again without a chain.

  $ echo '(executable (name main) (libraries broken))' > use-broken/dune
  $ touch use-broken/main.ml
  $ dune build ./use-broken/main.exe 2>&1 | dune_cmd subst "$PWD" PWD
  File "_build/default/.pkg/broken/dune", line 1, characters 31-44:
  Error: Unknown field "unknown_field"
  [1]

The unrelated target is still unaffected.

  $ dune build ./x 2>&1 | dune_cmd subst "$PWD" PWD
  
