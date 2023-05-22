Testing the "dune targets" command in a simple OCaml project with an additional
directory target to see the behaviour there.

We have two libraries with one in a subdirectory. We also have a directory
target d to see how the command will behave.

With no directory provided to the command, it should default to the current
working directory.

  $ dune targets
  .:
  a.ml
  d/
  dune
  dune-project
  simple.a
  simple.cma
  simple.cmxa
  simple.cmxs
  simple.ml-gen
  

Multiple directories can be provided to the command. Also subdirectories may be
used, and only the targets available in that directory will be displayed.

  $ dune targets . b/
  .:
  a.ml
  d/
  dune
  dune-project
  simple.a
  simple.cma
  simple.cmxa
  simple.cmxs
  simple.ml-gen
  
  
  b:
  c.ml
  dune
  simple2.a
  simple2.cma
  simple2.cmxa
  simple2.cmxs
  simple2.ml-gen
  

The command also works with files in the _build directory.

  $ dune targets _build/default/
  _build/default:
  a.ml
  d/
  dune
  dune-project
  simple.a
  simple.cma
  simple.cmxa
  simple.cmxs
  simple.ml-gen
  

  $ dune targets _build/default/b
  _build/default/b:
  c.ml
  dune
  simple2.a
  simple2.cma
  simple2.cmxa
  simple2.cmxs
  simple2.ml-gen
  
We cannot see inside directory targets

  $ dune targets d
  d:
  
  
Testing the --aliases command too:

  $ dune targets --aliases
  .:
  a.ml
  d/
  dune
  dune-project
  simple.a
  simple.cma
  simple.cmxa
  simple.cmxs
  simple.ml-gen
  @all
  @check
  @default
  @doc-private
  @fmt
