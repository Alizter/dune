A mounted package resolves an executable exported by another mounted package.
Programs not supplied by the lock still fall back to the invoking user's PATH.
Neither package enters the legacy package rules.

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
  >  (libraries foo))
  > EOF
  $ cat > main.ml <<'EOF'
  > let () = print_endline Foo.message
  > EOF

  $ mkdir tool
  $ cat > tool/dune-project <<'EOF'
  > (lang dune 3.20)
  > (package (name tool))
  > EOF
  $ cat > tool/dune <<'EOF'
  > (executable
  >  (name gen)
  >  (public_name mounted-gen)
  >  (package tool))
  > EOF
  $ cat > tool/gen.ml <<'EOF'
  > let () =
  >   let output = open_out Sys.argv.(1) in
  >   output_string output "let value = \"from-mounted-tool\"\n";
  >   close_out output
  > EOF
  $ tar cf tool.tar tool
  $ rm -rf tool

  $ mkdir foo
  $ cat > foo/dune-project <<'EOF'
  > (lang dune 3.20)
  > (package
  >  (name foo)
  >  (depends tool))
  > EOF
  $ cat > foo/dune <<'EOF'
  > (rule
  >  (targets generated.ml path_marker.ml)
  >  (action
  >   (progn
  >    (run %{bin:mounted-gen} generated.ml)
  >    (run path-helper path_marker.ml))))
  > (library
  >  (name foo)
  >  (public_name foo)
  >  (modules foo generated path_marker))
  > EOF
  $ cat > foo/foo.ml <<'EOF'
  > let message = Generated.value ^ ":" ^ Path_marker.value
  > EOF
  $ tar cf foo.tar foo
  $ rm -rf foo

  $ mkdir bin
  $ cat > bin/path-helper <<'EOF'
  > #!/bin/sh
  > printf 'let value = "from-user-path"\n' > "$1"
  > EOF
  $ chmod +x bin/path-helper

  $ make_lockdir
  $ make_lockpkg tool <<EOF
  > (version 1.0)
  > (source
  >  (fetch
  >   (url file://$PWD/tool.tar)
  >   (checksum md5=$(md5sum tool.tar | cut -f1 -d' '))))
  > (dune)
  > EOF
  $ make_lockpkg foo <<EOF
  > (version 1.0)
  > (depends tool)
  > (source
  >  (fetch
  >   (url file://$PWD/foo.tar)
  >   (checksum md5=$(md5sum foo.tar | cut -f1 -d' '))))
  > (build (run dune build @install))
  > EOF

  $ real_dune="$(command -v dune)"
  $ PATH="$PWD/bin:$PATH" "$real_dune" build ./main.exe --display quiet
  $ ./_build/default/main.exe
  from-mounted-tool:from-user-path

The lock's implicit Dune marker dispatches [tool] natively, while [foo] uses a
translated [dune build] action. Both tools and generated files belong to their
explicit mounted artifact roots. Looking up the executable must not instantiate
either package's old rules.

  $ tool_root=$(echo _build/_default+lockfile/pkg/tool.1.0-*)
  $ foo_root=$(echo _build/_default+lockfile/pkg/foo.1.0-*)
  $ test -x "$tool_root/gen.exe" && echo mounted-tool-artifact
  mounted-tool-artifact
  $ test -f "$foo_root/generated.ml" && test -f "$foo_root/path_marker.ml" && echo mounted-generated-artifacts
  mounted-generated-artifacts
  $ test ! -e _build/_private/default/.pkg/tool.1.0-* && test ! -e _build/_private/default/.pkg/foo.1.0-* && echo no-old-package-rules
  no-old-package-rules

Dune load records a separate span for each mounted package.

  $ dune trace cat | jq -c '
  > select(.cat == "rules" and .name == "mounted-dune-load")
  > | {context: .args.context, package: .args.package}
  > ' | sort
  {"context":"default","package":"foo"}
  {"context":"default","package":"tool"}

Mounted-package discovery itself runs once per context.

  $ dune trace cat | jq -c -s '
  > [ .[] | select(.cat == "pkg" and .name == "mounted-packages-load") ]
  > | group_by(.args.context)
  > | map({context: .[0].args.context, count: length})
  > '
  [{"context":"default","count":1}]

Package digest table construction runs once for the project lock directory.

  $ dune trace cat | jq -s '
  > [ .[] | select(.cat == "pkg" and .name == "package-digest-table") ]
  > | {count: length, package_counts: map(.args.packages) | unique}
  > '
  {
    "count": 1,
    "package_counts": [
      2
    ]
  }

Looking up a system C compiler for a mounted package must not load binaries from
an unrelated legacy package. The package graph is acyclic: the legacy transition
package depends on the mounted package, whose foreign stubs use the system
compiler.

  $ mkdir binary-scope-cycle
  $ cd binary-scope-cycle
  $ cat > dune-workspace <<'EOF'
  > (lang dune 3.20)
  > (pkg enabled)
  > EOF
  $ cat > dune-project <<'EOF'
  > (lang dune 3.20)
  > (package
  >  (name workspace)
  >  (depends legacy-transition))
  > EOF

  $ mkdir mounted-foreign
  $ cat > mounted-foreign/dune-project <<'EOF'
  > (lang dune 3.20)
  > (package (name mounted-foreign))
  > EOF
  $ cat > mounted-foreign/dune <<'EOF'
  > (library
  >  (name mounted_foreign)
  >  (public_name mounted-foreign)
  >  (foreign_stubs
  >   (language c)
  >   (names mounted_stubs)))
  > EOF
  $ cat > mounted-foreign/mounted_foreign.ml <<'EOF'
  > external touch : unit -> unit = "mounted_touch"
  > EOF
  $ cat > mounted-foreign/mounted_stubs.c <<'EOF'
  > #include <caml/mlvalues.h>
  > CAMLprim value mounted_touch(value unit) {
  >   return Val_unit;
  > }
  > EOF
  $ tar cf mounted-foreign.tar mounted-foreign
  $ rm -rf mounted-foreign

  $ make_lockdir
  $ make_lockpkg mounted-foreign <<EOF
  > (version 1.0)
  > (depends dune)
  > (source
  >  (fetch
  >   (url file://$PWD/mounted-foreign.tar)
  >   (checksum md5=$(md5sum mounted-foreign.tar | cut -f1 -d' '))))
  > (build (run dune build -p %{pkg-self:name} -j %{jobs} @install))
  > EOF
  $ make_lockpkg legacy-transition <<'EOF'
  > (version transition)
  > (depends mounted-foreign)
  > EOF

  $ build_pkg legacy-transition && echo binary-lookup-complete
  binary-lookup-complete
