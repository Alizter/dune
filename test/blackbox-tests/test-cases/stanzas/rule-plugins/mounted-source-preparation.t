A mounted rule plugin runs in its nested definition directory within the
prepared source. It sees overlays and patches, and may write scratch files
without modifying the original source or the logical mount.

Build the plugin before enabling the lock directory, so its RPC dependencies
need not be duplicated in the fixture's lock. Copy the executable into the
source; host/target executable selection is outside this test.

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
