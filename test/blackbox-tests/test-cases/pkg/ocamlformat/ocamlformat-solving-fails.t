When an OCamlFormat version does not exist, "dune fmt" would fail with a
solving error.

  $ . ./helpers.sh
  $ mkrepo

Make a project with no dependency on OCamlFormat.
  $ make_project_with_dev_tool_lockdir

Update ".ocamlformat" file with unknown version of OCamlFormat.
  $ cat > .ocamlformat <<EOF
  > version = 0.26.9
  > EOF

Format, it shows the solving error.
  $ DUNE_CONFIG__LOCK_DEV_TOOL=enabled dune fmt
  File "default/.dev-tool-locks/_unknown_", line 1, characters 0-0:
  Error: Couldn't solve the package dependency formula.
  The following packages couldn't be found: ocamlformat
  [1]
