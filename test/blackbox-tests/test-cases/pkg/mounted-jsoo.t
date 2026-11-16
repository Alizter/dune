A JS executable links the runtime files of its locked libraries. A natively
loaded locked library declares them with (javascript_files); an opaque locked
library's META names them in jsoo_runtime.

  $ make_lockdir
  $ cat > dune-project <<'EOF2'
  > (lang dune 3.25)
  > (package (name main) (allow_empty) (depends foo bar))
  > EOF2
  $ mkdir _foo _bar

[foo] is a dune project whose library ships a JavaScript primitive.

  $ cat > _foo/dune-project <<'EOF2'
  > (lang dune 3.25)
  > (package (name foo))
  > EOF2
  $ cat > _foo/dune <<'EOF2'
  > (library (public_name foo) (js_of_ocaml (javascript_files foo_runtime.js)))
  > EOF2
  $ cat > _foo/foo.ml <<'EOF2'
  > external prim : unit -> int = "foo_prim"
  > let value = prim ()
  > EOF2
  $ cat > _foo/foo_runtime.js <<'EOF2'
  > //Provides: foo_prim
  > function foo_prim(unit) { return 42; }
  > EOF2
  $ make_lockpkg foo <<EOF2
  > (version 1.0)
  > (source (copy $PWD/_foo))
  > (build (run false))
  > EOF2

[bar] is built by its recipe and installs a findlib package whose META names
the runtime file.

  $ cat > _bar/bar.ml <<'EOF2'
  > external prim : unit -> int = "bar_prim"
  > let value = prim ()
  > EOF2
  $ cat > _bar/bar_runtime.js <<'EOF2'
  > //Provides: bar_prim
  > function bar_prim(unit) { return 7; }
  > EOF2
  $ make_lockpkg bar <<EOF2
  > (version 1.0)
  > (source (copy $PWD/_bar))
  > (build
  >  (progn
  >   (run ocamlc -g -a -o bar.cma bar.ml)
  >   (write-file META "archive(byte) = \"bar.cma\"\njsoo_runtime = \"bar_runtime.js\"\n")
  >   (write-file bar.install "lib: [ \"META\" \"bar.cmi\" \"bar.cma\" \"bar_runtime.js\" ]")))
  > EOF2

One JS executable uses each.

  $ cat > dune <<'EOF2'
  > (dirs :standard \ _foo _bar)
  > (executable (name mounted) (modules mounted) (modes js) (libraries foo))
  > (executable (name opaque) (modules opaque) (modes js) (libraries bar))
  > EOF2
  $ echo 'let () = print_endline (string_of_int Foo.value)' > mounted.ml
  $ echo 'let () = print_endline (string_of_int Bar.value)' > opaque.ml
  $ dune build mounted.bc.js
  $ node _build/default/mounted.bc.js
  42
  $ dune build opaque.bc.js
  $ node _build/default/opaque.bc.js
  7
