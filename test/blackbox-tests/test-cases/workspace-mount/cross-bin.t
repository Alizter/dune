An executable lives in a mounted source tree; the workspace references
it via [%{bin:...}]. The Artifacts.t sibling fallback in the rules
layer resolves the cross-mount binary.

Mount: a public executable [helper].

  $ mkdir mount-src
  $ cat > mount-src/dune-project << EOF
  > (lang dune 3.25)
  > (package (name helper))
  > EOF
  $ cat > mount-src/dune << EOF
  > (executable
  >  (name helper)
  >  (public_name helper))
  > EOF
  $ cat > mount-src/helper.ml << EOF
  > let () = print_endline "hello from helper"
  > EOF

Workspace: a rule that runs [%{bin:helper}].

  $ mkdir wksp
  $ cd wksp
  $ cat > dune-project << EOF
  > (lang dune 3.25)
  > EOF
  $ cat > dune << EOF
  > (rule
  >  (target out)
  >  (action (with-stdout-to %{target} (run %{bin:helper}))))
  > EOF
  $ cat > dune-workspace << EOF
  > (lang dune 3.25)
  > (context
  >  (default
  >   (mount $PWD/../mount-src)))
  > EOF

Mount-context build of the executable on its own:

  $ dune build _build/default.mount-src/helper.exe
  $ test -f _build/default.mount-src/helper.exe && echo built
  built

Workspace context now resolves [%{bin:helper}] via the sibling
fallback. The rule runs successfully and writes the helper's output to
[out].

  $ dune build out
  $ cat _build/default/out
  hello from helper
