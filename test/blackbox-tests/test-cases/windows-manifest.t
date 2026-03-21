Test that the (windows_manifest ...) stanza builds successfully and embeds
the manifest in the executable.

  $ cat > dune-project <<EOF
  > (lang dune 3.23)
  > (using unreleased 0.1)
  > EOF

  $ cat > dune <<EOF
  > (executable
  >  (name tool)
  >  (windows_manifest tool.manifest))
  > EOF

  $ cat > tool.ml <<EOF
  > let () = Array.iter print_endline (Array.sub Sys.argv 1 (Array.length Sys.argv - 1))
  > EOF

  $ cat > tool.manifest <<EOF
  > <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  > <assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  >   <application xmlns="urn:schemas-microsoft-com:asm.v3">
  >     <windowsSettings>
  >       <longPathAware xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">true</longPathAware>
  >     </windowsSettings>
  >   </application>
  > </assembly>
  > EOF

  $ dune build 2>&1

  $ test -f _build/default/tool.exe

Verify that the manifest is actually embedded in the PE binary:

  $ strings _build/default/tool.exe | grep -c longPathAware
  1
