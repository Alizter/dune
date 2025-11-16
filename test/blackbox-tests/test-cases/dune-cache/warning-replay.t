Test that warnings are replayed when restored from shared cache.

  $ export XDG_RUNTIME_DIR=$PWD/.xdg-runtime
  $ export XDG_CACHE_HOME=$PWD/.xdg-cache

  $ cat > config <<EOF
  > (lang dune 3.0)
  > (cache enabled)
  > (cache-storage-mode copy)
  > EOF

  $ cat > dune-project <<EOF
  > (lang dune 3.0)
  > EOF

  $ cat > dune <<EOF
  > (library
  >  (name foo)
  >  (flags :standard -warn-error -A))
  > EOF

  $ cat > foo.ml <<EOF
  > let unused = 42
  > let f x = x + 1
  > EOF

  $ cat > foo.mli <<EOF
  > val f : int -> int
  > EOF

First build - populates shared cache:

  $ dune build --config-file=config
  File "foo.ml", line 1, characters 4-10:
  1 | let unused = 42
          ^^^^^^
  Warning 32 [unused-value-declaration]: unused value unused.
  
  File "foo.ml", line 1, characters 4-10:
  1 | let unused = 42
          ^^^^^^
  Warning 32 [unused-value-declaration]: unused value unused.
  


Clean workspace but keep shared cache:

  $ rm -rf _build/default

Rebuild from shared cache - warnings should be replayed:

  $ dune build --config-file=config
  File "foo.ml", line 1, characters 4-10:
  1 | let unused = 42
          ^^^^^^
  Warning 32 [unused-value-declaration]: unused value unused.
  
  File "foo.ml", line 1, characters 4-10:
  1 | let unused = 42
          ^^^^^^
  Warning 32 [unused-value-declaration]: unused value unused.
  

