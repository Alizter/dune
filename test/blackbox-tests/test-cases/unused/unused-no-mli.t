Modules without .mli produce no [intf] UIDs, so nothing to check.

  $ cat > dune-project <<EOF
  > (lang dune 3.23)
  > EOF

  $ cat > dune <<EOF
  > (executable
  >  (name main)
  >  (modules main helper))
  > EOF

  $ cat > main.ml <<EOF
  > let () = print_int (Helper.used 1)
  > EOF

  $ cat > helper.ml <<EOF
  > let used x = x + 1
  > let not_used x = x * 2
  > EOF

No .mli means no explicit exports to check:

  $ dune build @unused
