An executable lives in a mounted source tree; the workspace references
it via %{bin:...}. This pins the current behaviour for cross-mount
binary resolution.

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

Workspace: a rule that runs %{bin:helper}.

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

Workspace context cannot resolve [%{bin:helper}] because the binary
artifact lookup, like library scope, is workspace-only and does not
include the mount's executable (task #25 / #26 — per-context scope
and per-context install/binary enumeration).

  $ dune build out 2>&1 | head -5
  File "dune", line 3, characters 40-53:
  3 |  (action (with-stdout-to %{target} (run %{bin:helper}))))
                                              ^^^^^^^^^^^^^
  Error: Program helper not found in the tree or in PATH
   (context: default)
  [1]
