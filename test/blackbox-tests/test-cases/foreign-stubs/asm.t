Here we test the assembly language rules for stubs and foreign libraries.

  $ cat > dune-project <<EOF
  > (lang dune 3.25)
  > EOF

We build an archive from an assembly file, without mixed-language declarations
or language inference.

  $ cat > dune <<EOF
  > (foreign_library
  >  (names hello)
  >  (language asm)
  >  (archive_name mylib))
  > EOF

We add a rule for building the assembly file. This will not interfere with our archive.
  $ cat >> dune <<EOF
  > (rule
  >  (enabled_if
  >   (<> %{system} "win32"))
  >  (target hello.s)
  >  (deps
  >   (sandbox always)
  >   hello.c)
  >  (action
  >   (progn
  >    (run %{ocaml-config:c_compiler} -S hello.c))))
  > 
  > (rule
  >  (enabled_if
  >   (= %{system} "win32"))
  >  (target hello.asm)
  >  (deps
  >   (sandbox always)
  >   hello.c)
  >  (action
  >   (progn
  >    (run %{ocaml-config:c_compiler} /FA hello.c))))
  > EOF

Here is the C file we will turn into assembly.
  $ cat > hello.c <<EOF
  > char *message() { return "Hello, world!\n"; };
  > EOF

We can build the archive.
  $ dune build libmylib.a

We test that the contents of the archive contain our message.
  $ nm _build/default/libmylib.a | grep message > /dev/null

Assembly sources are not mistaken for C sources in the compilation database.

  $ dune build @check
  $ jq -c 'map(.file)' compile_commands.json
  []

The assembly language is versioned.

  $ make_dune_project 3.24
  $ dune build
  File "dune", line 3, characters 11-14:
  3 |  (language asm)
                 ^^^
  Error: 'asm' is only available since version 3.25 of the dune language.
  Please update your dune-project file to have (lang dune 3.25).
  [1]

Use a mock MSVC toolchain to check assembler selection on any host. The mock
compilers write their arguments to the object file instead of assembling it.
Dune must invoke ml64 with MASM options, not the C compiler.

  $ mkdir msvc
  $ cd msvc
  $ make_dune_project 3.25
  $ actual_ocamlc=$(command -v ocamlc)
  $ cat > ocamlc-msvc <<EOF
  > #!/bin/sh
  > if [ "\$1" = "-config" ]; then
  >   "$actual_ocamlc" -config | sed \
  >     -e 's/^ccomp_type:.*/ccomp_type: msvc/' \
  >     -e 's/^architecture:.*/architecture: amd64/' \
  >     -e 's/^os_type:.*/os_type: Win32/' \
  >     -e 's/^system:.*/system: win64/' \
  >     -e 's/^ext_obj:.*/ext_obj: .obj/' \
  >     -e 's|^c_compiler:.*|c_compiler: $PWD/c-compiler|'
  > else
  >   exec "$actual_ocamlc" "\$@"
  > fi
  > EOF
  $ cat > findlib.conf <<EOF
  > path=""
  > ocamlc="$PWD/ocamlc-msvc"
  > EOF
  $ cat > c-compiler <<'EOF'
  > #!/bin/sh
  > case "$1" in
  >   -c) output=$3 ;;
  >   /nologo) output=${3#/Fo} ;;
  >   *) exit 1 ;;
  > esac
  > printf '%s\n' "$(basename "$0")" "$@" > "$output"
  > EOF
  $ cp c-compiler ml64
  $ chmod +x ocamlc-msvc c-compiler ml64
  $ unset OCAMLFIND_TOOLCHAIN
  $ export OCAMLFIND_CONF="$PWD/findlib.conf"
  $ export PATH="$PWD:$PATH"
  $ cat > dune <<'EOF'
  > (foreign_library
  >  (archive_name msvc)
  >  (language asm)
  >  (names "hello world"))
  > EOF
  $ touch 'hello world.asm'
  $ dune build '"hello world.obj"'
  $ cat '_build/default/hello world.obj'
  ml64
  /nologo
  /quiet
  /Fohello world.obj
  /c
  hello world.asm

MinGW still uses the C compiler driver, despite targeting Windows.

  $ sed \
  >   -e 's/ccomp_type: msvc/ccomp_type: cc/' \
  >   -e 's/system: win64/system: mingw64/' \
  >   -e 's/ext_obj: .obj/ext_obj: .o/' \
  >   ocamlc-msvc > ocamlc-mingw
  $ chmod +x ocamlc-mingw
  $ sed 's/ocamlc-msvc/ocamlc-mingw/' findlib.conf > mingw.conf
  $ export OCAMLFIND_CONF="$PWD/mingw.conf"
  $ mv 'hello world.asm' 'hello world.S'
  $ dune build '"hello world.o"'
  $ cat '_build/default/hello world.o'
  c-compiler
  -c
  -o
  hello world.o
  hello world.S

Do not silently assemble for x86-64 when targeting a different architecture.

  $ sed 's/architecture: amd64/architecture: arm64/' ocamlc-msvc > ocamlc-arm
  $ chmod +x ocamlc-arm
  $ sed 's/ocamlc-msvc/ocamlc-arm/' findlib.conf > arm.conf
  $ export OCAMLFIND_CONF="$PWD/arm.conf"
  $ dune build '"hello world.obj"'
  File "dune", line 4, characters 8-21:
  4 |  (names "hello world"))
              ^^^^^^^^^^^^^
  Error: MSVC assembly requires x86-64, not arm64.
  [1]
