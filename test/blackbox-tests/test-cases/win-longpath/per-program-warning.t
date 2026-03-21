When dune invokes a tool with a long path argument, it should emit a
per-program warning if the tool lacks a longPathAware manifest.
If the tool has a manifest, no per-program warning should appear.

Build two tools: one with manifest, one without.

  $ cat > dune-project <<EOF
  > (lang dune 3.23)
  > (using unreleased 0.1)
  > EOF

  $ cat > with_manifest.ml <<EOF
  > let () = Array.iter print_endline (Array.sub Sys.argv 1 (Array.length Sys.argv - 1))
  > EOF

  $ cat > with_manifest.manifest <<EOF
  > <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  > <assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  >   <application xmlns="urn:schemas-microsoft-com:asm.v3">
  >     <windowsSettings>
  >       <longPathAware xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">true</longPathAware>
  >     </windowsSettings>
  >   </application>
  > </assembly>
  > EOF

  $ cat > without_manifest.ml <<EOF
  > let () = Array.iter print_endline (Array.sub Sys.argv 1 (Array.length Sys.argv - 1))
  > EOF

  $ cat > dune <<EOF
  > (executable
  >  (name with_manifest)
  >  (windows_manifest with_manifest.manifest))
  > (executable
  >  (name without_manifest))
  > (rule
  >  (alias test-with-manifest)
  >  (action (run ./with_manifest.exe "$long_path_arg")))
  > (rule
  >  (alias test-without-manifest)
  >  (action (run ./without_manifest.exe "$long_path_arg")))
  > EOF

Verify the manifest is embedded:

  $ dune build
  $ strings _build/default/with_manifest.exe | grep -c longPathAware
  1

Tool WITH manifest — no per-program warning expected:

  $ DUNE_LONG_PATH_ENABLED=true dune build @test-with-manifest 2>&1 | sanitize_long_path_output
  some/path/<LONG_PATH>

  $ dune trace cat | jq -c 'select(.args.message? == "Long_path_check.check_pe_manifest") | {prog: .args.prog, result: .args.result}'
  {"prog":["In_build_dir",".sandbox/34fe8262f39422cd5facdd363eeadb58/default/with_manifest.exe"],"result":true}
  $ dune trace cat | jq -c 'select(.args.message? == "Long_path_check.check_pe_manifest failed") | {prog: .args.prog, exn: .args.exn}'

Tool WITHOUT manifest — per-program warning expected:

  $ DUNE_LONG_PATH_ENABLED=true dune build @test-without-manifest 2>&1 | sanitize_long_path_output
  Warning:
  _build/.sandbox/<HASH>/default/without_manifest.exe
  does not appear to support long paths, but dune is passing a path of NNN
  characters. The build may fail unless
  _build/.sandbox/<HASH>/default/without_manifest.exe
  has a longPathAware manifest or LongPathsEnabled is set system-wide.
  some/path/<LONG_PATH>
