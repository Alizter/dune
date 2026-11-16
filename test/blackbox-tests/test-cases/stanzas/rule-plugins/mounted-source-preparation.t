A mounted rule plugin runs in its nested definition directory within the
prepared source. It sees overlays and patches, and may write scratch files
without modifying the original source or the logical mount.

Start with a prebuilt plugin so the source-preparation checks do not depend on
its build rules. The last case compiles a fresh executable from mounted source.

  $ cat > dune-project <<'EOF'
  > (lang dune 3.26)
  > EOF
  $ mkdir driver
  $ cat > driver/dune <<'EOF'
  > (executable
  >  (name rules)
  >  (libraries dune-rules-plugin-lwt lwt.unix))
  > EOF
  $ cat > driver/rules.ml <<'EOF'
  > open Dune_rules_plugin_lwt
  > let load_rules _ =
  >   let input = open_in "input.txt" in
  >   let contents = input_line input in
  >   close_in input;
  >   let scratch = open_out "scratch" in
  >   output_string scratch "plugin wrote here\n";
  >   close_out scratch;
  >   [ Sexp.List
  >       [ Sexp.atom "rule"
  >       ; List [ Sexp.atom "target"; Sexp.atom "result" ]
  >       ; List
  >           [ Sexp.atom "action"
  >           ; List
  >               [ Sexp.atom "write-file"
  >               ; Sexp.atom "result"
  >               ; Quoted_string (contents ^ "\n")
  >               ]
  >           ]
  >       ]
  >   ]
  > ;;
  > let () = Lwt_main.run (run (Lwt.wrap1 load_rules))
  > EOF
  $ dune build driver/rules.exe

The plugin is defined below the package root, and invoked from a different
directory. Its relative input must come from the definition directory, not
from the invocation directory or the package root.

  $ mkdir -p _source/tools/generator _source/use _overlay
  $ cp _build/default/driver/rules.exe _source/tools/generator/rules.exe
  $ cat > _source/dune-project <<'EOF'
  > (lang dune 3.26)
  > (using plugin 0.1)
  > (package (name foo) (dir .))
  > EOF
  $ cat > _source/tools/generator/dune <<'EOF'
  > (plugin
  >  (name generate)
  >  (executable ./rules.exe))
  > EOF
  $ echo '(plugin.generate)' > _source/use/dune
  $ echo original > _source/tools/generator/input.txt
  $ echo overlay > _overlay/input.txt
  $ cat > dune-project <<'EOF'
  > (lang dune 3.26)
  > (package (name main) (depends foo))
  > EOF
  $ cat > dune-workspace <<'EOF'
  > (lang dune 3.26)
  > (pkg enabled)
  > EOF
  $ make_lockdir
  $ make_lockpkg foo <<EOF
  > (version 1.0)
  > (source (copy $PWD/_source))
  > (extra_sources
  >  (tools/generator/input.txt (copy $PWD/_overlay/input.txt)))
  > (build (progn (patch update.patch) (run false)))
  > EOF
  $ make_lockpkg_file foo update.patch <<'EOF'
  > --- a/tools/generator/input.txt
  > +++ b/tools/generator/input.txt
  > @@ -1 +1 @@
  > -overlay
  > +patched
  > EOF

The generated rule observes the patched overlay. The unusable recipe ensures
that this is a native mount, not an opaque package build.

  $ dune build _build/default/.pkg/foo/use/result
  $ cat _build/default/.pkg/foo/use/result
  patched
  $ cat _source/tools/generator/input.txt _overlay/input.txt
  original
  overlay
  $ test ! -e _source/tools/generator/scratch
  $ test ! -e _build/default/.pkg/foo/tools/generator/scratch

A plugin's package must also be mounted in the host context. Its presence in
only the target lock must not make Dune build or run the target executable.

  $ source_lock_dir=host.lock make_lockdir
  $ cat > dune-workspace <<'EOF'
  > (lang dune 3.26)
  > (pkg enabled)
  > (context (default (name host) (lock_dir host.lock)))
  > (context (default (name target) (host host) (lock_dir dune.lock)))
  > EOF
  $ dune build _build/target/.pkg/foo/use/result
  Error: No rule found for .pkg/foo/tools/generator/rules.exe (context host)
  -> required by rule plugin generate
  [1]
  $ test ! -e _build/target/.pkg/foo/tools/generator/rules.exe
  $ test ! -e _build/target/.pkg/foo/use/result

Adding the package to the host lock restores rule generation. Only the host
copy of the executable is built, while the generated target is in the target
context and still sees the prepared overlay.

  $ cp dune.lock/foo.pkg host.lock/foo.pkg
  $ cp -R dune.lock/foo.files host.lock/foo.files
  $ dune build _build/target/.pkg/foo/use/result
  $ cat _build/target/.pkg/foo/use/result
  patched
  $ test -f _build/host/.pkg/foo/tools/generator/rules.exe
  $ test ! -e _build/target/.pkg/foo/tools/generator/rules.exe
  $ test ! -e _source/tools/generator/scratch
  $ test ! -e _build/host/.pkg/foo/tools/generator/scratch
  $ test ! -e _build/target/.pkg/foo/tools/generator/scratch

Now compile the plugin from its mounted OCaml source. The SDK path is an
explicit fixture input, independent of locked-library visibility and exported
environment policy. Different host and target patches identify the prepared
working tree used by the compiled plugin. Successful compiler output is saved:
duplicate findlib SDK warnings depend on the surrounding installation. Build
failures still print the complete output.

  $ cp driver/rules.ml _source/tools/generator/rules.ml
  $ printf '%s' "$OCAMLPATH" > _source/tools/generator/sdk-path
  $ cat > _source/tools/generator/dune <<'EOF'
  > (rule
  >  (targets compiled.exe rules.cmi rules.cmo compiled-in)
  >  (deps rules.ml)
  >  (action
  >   (progn
  >    (write-file compiled-in %{context_name})
  >    (setenv OCAMLPATH %{read:sdk-path}
  >     (run %{bin:ocamlfind} ocamlc -custom -thread
  >      -package dune-rules-plugin-lwt,lwt.unix -linkpkg
  >      -o compiled.exe rules.ml)))))
  > (plugin
  >  (name generate)
  >  (executable ./compiled.exe))
  > EOF
  $ source_lock_dir=host.lock make_lockpkg_file foo update.patch <<'EOF'
  > --- a/tools/generator/input.txt
  > +++ b/tools/generator/input.txt
  > @@ -1 +1 @@
  > -overlay
  > +host-prepared
  > EOF
  $ test ! -e _source/tools/generator/compiled.exe
  $ dune build _build/target/.pkg/foo/use/result > compile-output 2>&1 ||
  >   { cat compile-output; false; }
  $ cat _build/target/.pkg/foo/use/result
  host-prepared
  $ cat _build/host/.pkg/foo/tools/generator/compiled-in
  host
  $ test -f _build/host/.pkg/foo/tools/generator/compiled.exe
  $ test ! -e _build/target/.pkg/foo/tools/generator/compiled.exe
  $ test ! -e _build/target/.pkg/foo/tools/generator/compiled-in
  $ test ! -e _source/tools/generator/compiled.exe
  $ test ! -e _source/tools/generator/rules.cmi
  $ test ! -e _source/tools/generator/scratch
  $ test ! -e _build/host/.pkg/foo/tools/generator/scratch
  $ test ! -e _build/target/.pkg/foo/tools/generator/scratch
