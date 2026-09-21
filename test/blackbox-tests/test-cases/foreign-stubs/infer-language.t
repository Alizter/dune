Language inference works without the languages field or assembly support.

  $ make_dune_project 3.26
  $ cat > foo.c <<'EOF'
  > #include <caml/mlvalues.h>
  > CAMLprim value hello_c(value unit) {
  >   (void)unit;
  >   return Val_int(40);
  > }
  > EOF
  $ cat > bar.cpp <<'EOF'
  > #ifndef __cplusplus
  > #error Not a C++ compiler
  > #endif
  > #include <caml/mlvalues.h>
  > extern "C" CAMLprim value hello_cpp(value unit) {
  >   (void)unit;
  >   return Val_int(2);
  > }
  > EOF
  $ cat > main.ml <<'EOF'
  > external hello_c : unit -> int = "hello_c"
  > external hello_cpp : unit -> int = "hello_cpp"
  > let () = Printf.printf "%d\n" (hello_c () + hello_cpp ())
  > EOF

Omitting language selects sources by their extensions, including :standard.

  $ cat > dune <<'EOF'
  > (executable
  >  (name main)
  >  (foreign_stubs))
  > EOF
  $ dune exec ./main.exe
  42
  $ dune build @check
  $ jq -r '.[].file' compile_commands.json | sort
  bar.cpp
  foo.c

Foreign archives also support inference.

  $ cat > dune <<'EOF'
  > (foreign_library
  >  (archive_name mixed)
  >  (names foo bar))
  > (executable
  >  (name main)
  >  (foreign_archives mixed))
  > EOF
  $ dune exec ./main.exe
  42

Explicit language selection still disambiguates same-name sources.

  $ touch foo.cpp
  $ cat > dune <<'EOF'
  > (executable
  >  (name main)
  >  (foreign_stubs (language c) (names foo))
  >  (foreign_stubs (language cxx) (names bar)))
  > EOF
  $ dune exec ./main.exe
  42

Without an explicit language, the ambiguous source is rejected.

  $ cat > dune <<'EOF'
  > (executable
  >  (name main)
  >  (foreign_stubs (names foo bar)))
  > EOF
  $ dune build
  File "dune", line 3, characters 23-26:
  3 |  (foreign_stubs (names foo bar)))
                             ^^^
  Error: Multiple sources map to the same object name "foo":
  - foo.c
  - foo.cpp
  This is not allowed; please rename them or remove "foo" from object names.
  Hint: You can also avoid the name clash by placing the objects into different
  foreign archives and building them in different directories. Foreign archives
  can be defined using the (foreign_library ...) stanza.
  [1]

Older language versions still require the language field.

  $ make_dune_project 3.25
  $ dune build
  File "dune", line 3, characters 1-32:
  3 |  (foreign_stubs (names foo bar)))
       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: Field "language" is missing
  [1]
