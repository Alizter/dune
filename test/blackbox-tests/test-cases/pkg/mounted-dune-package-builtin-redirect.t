A mounted library remains reachable through Dune's built-in deprecated library
name redirects. The redirect's destination may be supplied by a selected lock
package rather than the ambient findlib database.

  $ cat > dune-workspace <<'EOF'
  > (lang dune 3.20)
  > (pkg enabled)
  > EOF
  $ cat > dune-project <<'EOF'
  > (lang dune 3.20)
  > (package
  >  (name main)
  >  (depends consumer))
  > EOF
  $ cat > dune <<'EOF'
  > (executable
  >  (name main)
  >  (libraries consumer))
  > EOF
  $ cat > main.ml <<'EOF'
  > let () = print_endline Consumer.message
  > EOF

  $ mkdir configurator
  $ cat > configurator/dune-project <<'EOF'
  > (lang dune 3.20)
  > (package (name dune-configurator))
  > EOF
  $ cat > configurator/dune <<'EOF'
  > (library
  >  (name configurator)
  >  (public_name dune-configurator))
  > EOF
  $ cat > configurator/configurator.ml <<'EOF'
  > let message = "redirected"
  > EOF
  $ tar cf configurator.tar configurator
  $ rm -rf configurator

  $ mkdir consumer
  $ cat > consumer/dune-project <<'EOF'
  > (lang dune 3.20)
  > (package
  >  (name consumer)
  >  (depends dune-configurator))
  > EOF
  $ cat > consumer/dune <<'EOF'
  > (library
  >  (name consumer)
  >  (public_name consumer)
  >  (libraries dune.configurator))
  > EOF
  $ cat > consumer/consumer.ml <<'EOF'
  > let message = Configurator.message
  > EOF
  $ tar cf consumer.tar consumer
  $ rm -rf consumer

  $ make_lockdir
  $ make_lockpkg dune-configurator <<EOF
  > (version 1.0)
  > (source (copy $PWD/configurator.tar))
  > (build (run dune build @install))
  > EOF
  $ make_lockpkg consumer <<EOF
  > (version 1.0)
  > (depends dune-configurator)
  > (source (copy $PWD/consumer.tar))
  > (build (run dune build @install))
  > EOF

  $ dune build ./main.exe --display quiet
  $ ./_build/default/main.exe
  redirected
