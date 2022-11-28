Testing the coq.ffi stanza with local libraries

  $ cat > dune << EOF
  > (coqffi
  >  (modules hello)
  >  (library hello))
  > 
  > (library
  >  (name hello)
  >  (modules hello))
  > 
  > (coq.theory
  >  (name hello))
  > EOF

  $ dune build
  File "dune", line 1, characters 0-42:
  1 | (coqffi
  2 |  (modules hello)
  3 |  (library hello))
  Error: No rule found for .hello.objs/hello.impl.all-deps
  [1]
  $ ls -a _build/default/ _build/default/.hello.objs/
  _build/default/:
  .
  ..
  .dune
  .hello.objs
  .merlin-conf
  hello.a
  hello.cma
  hello.cmxa
  hello.cmxs
  hello.ml
  hello.mli
  
  _build/default/.hello.objs/:
  .
  ..
  byte
  native

The coqffi stanza does not support libraries that were not installed using Dune

  $ cat > dune << EOF
  > (coqffi
  >  (modules unix)
  >  (library unix))
  > EOF

  $ dune build
  File "dune", line 1, characters 0-40:
  1 | (coqffi
  2 |  (modules unix)
  3 |  (library unix))
  Error: Library "unix" was not installed using Dune and is therefore not
  supported by the coqffi stanza.
  [1]

Testing the coqffi stanza with non-existant modules

  $ cat > dune << EOF
  > (coqffi
  >  (modules foo)
  >  (library hello))
  > 
  > (library
  >  (name hello)
  >  (modules hello))
  > EOF

  $ dune build
  File "dune", line 1, characters 0-40:
  1 | (coqffi
  2 |  (modules foo)
  3 |  (library hello))
  Error: Module "Foo" was not found in library "hello".
  [1]

Testing the coqffi stanza with flags

  $ cat > dune << EOF
  > (coqffi
  >  (modules hello)
  >  (library hello)
  >  (flags --some --flags))
  > 
  > (library
  >  (name hello)
  >  (modules hello))
  > EOF

  $ dune build
  File "dune", line 1, characters 0-66:
  1 | (coqffi
  2 |  (modules hello)
  3 |  (library hello)
  4 |  (flags --some --flags))
  Error: No rule found for .hello.objs/hello.impl.all-deps
  [1]
