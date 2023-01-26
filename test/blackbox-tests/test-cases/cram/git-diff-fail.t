We demonstrate the leaking of the display of internal processes when running
cram tests.

First we make a cram test:

  $ cat > dune-project << EOF
  > (lang dune 3.7)
  > EOF

  $ cat > mytest.t << EOF
  >   $ echo A
  >   B
  > EOF

We need to avoid the special treatment of the test when INSIDE_DUNE is set:
  $ unset INSIDE_DUNE

We do not observe the leaking of the display of internal processes when running
dune build. Note that we scrub the actual reported error due to the build tool
being bogus.
  $ dune build --root=. --diff-command="exit 1; echo" --display=short @runtest | sed '/^(cd/d' 
  File "mytest.t", line 1, characters 0-0:
  Command exited with code 1.
  [1]
