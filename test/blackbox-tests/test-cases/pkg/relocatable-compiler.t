Test that relocatable compiler packages are treated as regular packages
instead of being installed to the special toolchain cache directory.

  $ make_lockdir

Create a fake compiler directory with minimal structure:

  $ mkdir fake-compiler

  $ cat > fake-compiler/configure << 'EOF'
  > #!/bin/sh
  > PREFIX=$1
  > echo $PREFIX > prefix.txt
  > EOF

  $ chmod a+x fake-compiler/configure

  $ mkdir -p fake-compiler/target/bin

  $ cat > fake-compiler/target/bin/ocamlc << EOF
  > #!/bin/sh
  > echo "Hello from fake ocamlc!"
  > EOF

  $ chmod a+x fake-compiler/target/bin/ocamlc

  $ cat > fake-compiler/Makefile << 'EOF'
  > prefix := $(shell cat prefix.txt)
  > target := $(DESTDIR)$(prefix)
  > install:
  > 	@mkdir -p $(target)
  > 	@cp -r target/* $(target)
  > EOF

First, test that a non-relocatable compiler gets installed to the toolchains
cache directory (existing behavior):

  $ make_lockpkg ocaml-base-compiler << EOF
  > (version 1)
  > (build
  >  (run ./configure %{prefix}))
  > (install
  >  (run %{make} install))
  > (source
  >  (copy $PWD/fake-compiler))
  > EOF

  $ cat > dune-project << EOF
  > (lang dune 3.16)
  > (package
  >  (name foo)
  >  (depends ocaml-base-compiler))
  > EOF

  $ cat > dune << EOF
  > (executable
  >  (public_name foo))
  > EOF

  $ cat > foo.ml << EOF
  > print_endline "Hello, World!"
  > EOF

  $ remove_hash() {
  >   dune_cmd subst 'ocaml-base-compiler.1-[^/]+' 'ocaml-base-compiler.1-HASH'
  > }

Build with toolchains enabled - should install to toolchain cache:

  $ XDG_CACHE_HOME=$PWD/cache1 DUNE_CONFIG__TOOLCHAINS=enabled build_pkg ocaml-base-compiler

Verify the toolchain was installed to the cache directory:

  $ find cache1/dune/toolchains 2>/dev/null | sort | remove_hash
  cache1/dune/toolchains
  cache1/dune/toolchains/ocaml-base-compiler.1-HASH
  cache1/dune/toolchains/ocaml-base-compiler.1-HASH/target
  cache1/dune/toolchains/ocaml-base-compiler.1-HASH/target/bin
  cache1/dune/toolchains/ocaml-base-compiler.1-HASH/target/bin/ocamlc

Now test that a relocatable compiler (with relocatable-compiler in the lock)
is treated as a regular package and NOT installed to the toolchain cache.

The real layout from dra27's opam-repository is:
- relocatable-compiler: the actual compiler build (depends on compiler-cloning)
- ocaml-compiler: virtual package (depends on relocatable-compiler)
- ocaml-base-compiler: virtual package (depends on ocaml-compiler)

  $ rm -rf dune.lock _build cache1

  $ make_lockdir

Create compiler-cloning (virtual package):

  $ make_lockpkg compiler-cloning << EOF
  > (version enabled)
  > EOF

Create relocatable-compiler (the actual compiler package):

  $ make_lockpkg relocatable-compiler << EOF
  > (version 1)
  > (depends compiler-cloning)
  > (build
  >  (run ./configure %{prefix}))
  > (install
  >  (run %{make} install))
  > (source
  >  (copy $PWD/fake-compiler))
  > EOF

Create ocaml-compiler (depends on relocatable-compiler):

  $ make_lockpkg ocaml-compiler << EOF
  > (version 1)
  > (depends relocatable-compiler)
  > EOF

Create ocaml-base-compiler (depends on ocaml-compiler):

  $ make_lockpkg ocaml-base-compiler << EOF
  > (version 1)
  > (depends ocaml-compiler)
  > EOF

  $ cat > dune-project << EOF
  > (lang dune 3.16)
  > (package
  >  (name foo)
  >  (depends ocaml-base-compiler))
  > EOF

Build with toolchains enabled - should NOT install to toolchain cache
because relocatable-compiler is present:

  $ XDG_CACHE_HOME=$PWD/cache2 DUNE_CONFIG__TOOLCHAINS=enabled build_pkg ocaml-base-compiler

Verify the toolchain cache directory is empty (relocatable compiler should
be installed as a regular package, not to the toolchain cache):

  $ find cache2/dune/toolchains 2>/dev/null | sort

The relocatable compiler package should be built as a regular package.
Show that the package targets exist in the normal build directory:

  $ show_pkg_targets relocatable-compiler
  
  /bin
  /bin/ocamlc
  /cookie
  /doc
  /doc/relocatable-compiler
  /etc
  /etc/relocatable-compiler
  /lib
  /lib/relocatable-compiler
  /lib/stublibs
  /lib/toplevel
  /man
  /sbin
  /share
  /share/relocatable-compiler


The ocaml-base-compiler package should also be treated as regular:

  $ show_pkg_targets ocaml-base-compiler
  
  /cookie

