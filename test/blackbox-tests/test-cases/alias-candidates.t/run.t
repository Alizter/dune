Dune should suggest similar aliases when it cannot find one. 

We have an alias "foo" but let's try to build something misspeled:
  $ dune build @fou
  Error: Alias "fou" specified on the command line is empty.
  It is not defined in . or any of its descendants.
  Hint: did you mean fmt or foo?
  [1]
