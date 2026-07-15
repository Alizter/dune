A locked package does not see files installed by a workspace dependency through
a source_trees entry.

  $ make_dune_project 3.24
  $ cat >> dune-project <<EOF
  > (package (name ws))
  > EOF
  $ mkdir -p src/docs/nested
  $ echo source-tree-data > src/docs/nested/data
  $ cat > src/dune <<EOF
  > (install
  >  (package ws)
  >  (section share)
  >  (source_trees docs))
  > EOF

Ordinary installation materialises the nested file:

  $ dune build @install
  $ test -f _build/install/default/share/ws/docs/nested/data

  $ make_lockdir
  $ make_lockpkg consumer <<'EOF'
  > (version 0.0.1)
  > (depends ws)
  > (build
  >  (system
  >   "if test -f %{pkg:ws:share}/docs/nested/data; then echo source-tree-visible; else echo source-tree-missing; fi"))
  > EOF
  $ write_lockdir_consumer_rule

The scoped workspace layout omits the source tree entry:

  $ dune build out
  source-tree-missing
