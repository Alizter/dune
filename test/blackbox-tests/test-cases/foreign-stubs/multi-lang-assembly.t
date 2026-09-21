Integration of assembly, explicit language lists, and language inference.

  $ make_dune_project 3.26
  $ cat > foo_c.c <<'EOF'
  > #include <caml/mlvalues.h>
  > CAMLprim value hello_c(value unit) {
  >   (void)unit;
  >   return Val_int(40);
  > }
  > EOF
  $ cat > foo_cpp.cpp <<'EOF'
  > #ifndef __cplusplus
  > #error Not a C++ compiler
  > #endif
  > #include <caml/mlvalues.h>
  > extern "C" CAMLprim value hello_cpp(value unit) {
  >   (void)unit;
  >   return Val_int(2);
  > }
  > EOF
  $ cat > foo_asm_source.c <<'EOF'
  > #include <caml/mlvalues.h>
  > CAMLprim value hello_asm(value unit) {
  >   (void)unit;
  >   return Val_int(3);
  > }
  > EOF
  $ cat > asm.inc <<'EOF'
  > (rule
  >  (target foo_asm.s)
  >  (deps foo_asm_source.c)
  >  (action
  >   (run %{ocaml-config:c_compiler}
  >    -I %{ocaml-config:standard_library} -S %{deps} -o %{target})))
  > EOF
  $ cat > main.ml <<'EOF'
  > external hello_c : unit -> int = "hello_c"
  > external hello_cpp : unit -> int = "hello_cpp"
  > external hello_asm : unit -> int = "hello_asm"
  > let () = Printf.printf "%d\n" (hello_c () + hello_cpp () + hello_asm ())
  > EOF

All three languages can be selected explicitly.

  $ cat > dune <<'EOF'
  > (include asm.inc)
  > (executable
  >  (name main)
  >  (foreign_stubs
  >   (languages c cxx asm)
  >   (names foo_c foo_cpp foo_asm)))
  > EOF
  $ dune exec ./main.exe
  45
  $ dune build @check
  $ jq -r '.[].file' compile_commands.json | sort
  foo_asm.s
  foo_c.c
  foo_cpp.cpp

Inference includes assembly as well as C and C++.

  $ cat > dune <<'EOF'
  > (include asm.inc)
  > (executable
  >  (name main)
  >  (foreign_stubs (names foo_c foo_cpp foo_asm)))
  > EOF
  $ dune exec ./main.exe
  45
  $ dune build compile_commands.json
  $ jq -r '.[].file' compile_commands.json | sort
  foo_asm.s
  foo_c.c
  foo_cpp.cpp

A single archive can combine all three languages.

  $ cat > dune <<'EOF'
  > (include asm.inc)
  > (foreign_library
  >  (archive_name mixed)
  >  (languages c cxx asm)
  >  (names foo_c foo_cpp foo_asm))
  > (executable
  >  (name main)
  >  (foreign_archives mixed))
  > EOF
  $ dune exec ./main.exe
  45
  $ dune build compile_commands.json
  $ jq -r '.[].file' compile_commands.json | sort
  foo_asm.s
  foo_c.c
  foo_cpp.cpp
