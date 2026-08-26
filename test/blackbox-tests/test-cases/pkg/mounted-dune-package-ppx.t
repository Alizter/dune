A mounted package may define a PPX driver and use it to preprocess its own
library. Its plain and OCaml-syntax Dune files may both use source include
stanzas, including a source include reached from a generated dynamic include. A
workspace consumer uses the same driver, resolving its libraries from
the mounted package without creating a second semantic workspace context.

  $ cat > dune-workspace <<'EOF'
  > (lang dune 3.20)
  > (pkg enabled)
  > EOF
  $ cat > dune-project <<'EOF'
  > (lang dune 3.20)
  > (package
  >  (name main)
  >  (depends foo))
  > EOF
  $ cat > dune <<'EOF'
  > (executable
  >  (name main)
  >  (libraries foo)
  >  (preprocess (staged_pps foo.ppx)))
  > EOF
  $ cat > main.ml <<'EOF'
  > let () = print_endline Foo.message
  > EOF

  $ mkdir -p foo/lib foo/generator
  $ cat > foo/dune-project <<'EOF'
  > (lang dune 3.24)
  > (package (name foo))
  > EOF
  $ cat > foo/lib/dune <<'EOF'
  > (include libraries.inc)
  > (rule
  >  (target foo.ml)
  >  (deps ../generator/proof.ml)
  >  (action (copy ../generator/proof.ml %{target})))
  > (dynamic_include ../generator/dynamic.inc)
  > EOF
  $ cat > foo/lib/libraries.inc <<'EOF'
  > (library
  >  (name foo)
  >  (public_name foo)
  >  (modules foo dynamic)
  >  (preprocess (staged_pps foo.ppx)))
  > (library
  >  (name foo_ppx_support)
  >  (public_name foo.ppx_support)
  >  (modules foo_ppx_support))
  > (library
  >  (name foo_ppx)
  >  (public_name foo.ppx)
  >  (modules foo_ppx)
  >  (kind ppx_rewriter)
  >  (libraries foo_ppx_support)
  >  (ppx.driver (main Foo_ppx.main)))
  > EOF
  $ cat > foo/lib/dynamic-source.inc <<'EOF'
  > (rule
  >  (target dynamic.ml)
  >  (action
  >   (with-stdout-to %{target}
  >    (echo "let value = \"include ppx\""))))
  > EOF
  $ cat > foo/lib/foo_ppx_support.ml <<'EOF'
  > let touch () = ()
  > EOF
  $ cat > foo/lib/foo_ppx.ml <<'EOF'
  > let main () =
  >   Foo_ppx_support.touch ();
  >   if Array.length Sys.argv >= 3 then (
  >     let input_file = Sys.argv.(Array.length Sys.argv - 2) in
  >     let output_file = Sys.argv.(Array.length Sys.argv - 1) in
  >     let input = open_in_bin input_file in
  >     let contents = really_input_string input (in_channel_length input) in
  >     close_in input;
  >     let output = open_out_bin output_file in
  >     output_string output contents;
  >     close_out output)
  >   else
  >     exit 2
  > EOF
  $ cat > foo/generator/dune-project <<'EOF'
  > (lang dune 3.24)
  > EOF
  $ cat > foo/generator/dune <<EOF
  > (* -*- tuareg -*- *)
  > let () =
  >   let count = open_out_gen [ Open_creat; Open_text; Open_append ] 0o666 "$PWD/eval-count" in
  >   output_string count "eval\n";
  >   close_out count
  > let () = Jbuild_plugin.V1.send {|
  > (include dune.inc)
  > (rule
  >  (with-stdout-to dynamic.inc
  >   (echo "(include dynamic-source.inc)")))
  > |}
  > EOF
  $ cat > foo/generator/dune.inc <<'EOF'
  > (rule
  >  (target proof.ml)
  >  (action
  >   (with-stdout-to %{target}
  >    (echo "let message = \"mounted \" ^ Dynamic.value"))))
  > EOF
  $ tar cf foo.tar foo
  $ rm -rf foo

  $ make_lockdir
  $ make_lockpkg foo <<EOF
  > (version 1.0)
  > (source
  >  (fetch
  >   (url file://$PWD/foo.tar)
  >   (checksum md5=$(md5sum foo.tar | cut -f1 -d' '))))
  > (build (run dune build @install))
  > EOF

  $ dune build ./main.exe --display quiet
  $ ./_build/default/main.exe
  mounted include ppx
  $ wc -l < eval-count
  1

A second process re-evaluates the mounted OCaml-syntax file once, while both
include paths retain snapshot ownership.

  $ dune build ./main.exe --display quiet
  $ ./_build/default/main.exe
  mounted include ppx
  $ wc -l < eval-count
  2

Static source metadata, including the source include reached from the generated
include, is read directly from the loaded source.

  $ foo_root=$(echo _build/_default+lockfile/pkg/foo.1.0-*)
  $ test ! -e "$foo_root/lib/libraries.inc" && echo static-include-not-materialized
  static-include-not-materialized
  $ test ! -e "$foo_root/lib/dynamic-source.inc" && echo dynamic-source-not-materialized
  dynamic-source-not-materialized

The package objects use the mounted artifact root. The synthesized PPX executable
is a tool of the workspace resolver and uses its ordinary [.ppx] directory.
Loading the driver does not instantiate the old package pipeline.

  $ foo_root=$(echo _build/_default+lockfile/pkg/foo.1.0-*)
  $ test -f "$foo_root/lib/.foo.objs/native/foo.cmx" && echo mounted-library-artifact
  mounted-library-artifact
  $ test -n "$(find _build/default/.ppx -name ppx.exe -print -quit)" && echo workspace-resolver-ppx
  workspace-resolver-ppx
  $ test ! -e _build/_private/default/.pkg/foo.1.0-* && echo no-old-package-rules
  no-old-package-rules
