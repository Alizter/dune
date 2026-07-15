Adding a workspace dependency directly to one provider must not reverse the
precedence of otherwise independent lockdir packages. Both provider packages
below install the same findlib package with distinct META versions.

  $ make_dune_project 3.24
  $ make_lockdir

  $ make_lockpkg provider-a <<EOF
  > (version 0.0.1)
  > (install
  >  (system "mkdir -p %{lib}/shared && echo 'version = \"provider-a\"' > %{lib}/shared/META"))
  > EOF
  $ make_lockpkg provider-b <<EOF
  > (version 0.0.1)
  > (install
  >  (system "mkdir -p %{lib}/shared && echo 'version = \"provider-b\"' > %{lib}/shared/META"))
  > EOF

  $ cat > dune <<'EOF'
  > (rule
  >  (target before.output)
  >  (action
  >   (with-stdout-to %{target}
  >    (run ocamlfind query -format %v shared))))
  > EOF
  $ dune build before.output

Add an empty workspace dependency directly to whichever provider currently
wins:

  $ cat >> dune-project <<EOF
  > (package
  >  (name ws-empty)
  >  (allow_empty))
  > EOF
  $ winner=$(cat _build/default/before.output)
  $ make_lockpkg "$winner" <<EOF
  > (version 0.0.1)
  > (depends ws-empty)
  > (install
  >  (system "mkdir -p %{lib}/shared && echo 'version = \"$winner\"' > %{lib}/shared/META"))
  > EOF
  $ cat >> dune <<'EOF'
  > (rule
  >  (target after.output)
  >  (action
  >   (with-stdout-to %{target}
  >    (run ocamlfind query -format %v shared))))
  > EOF
  $ dune build after.output

The same provider retains precedence:

  $ if cmp -s _build/default/before.output _build/default/after.output; then
  >   echo unchanged
  > else
  >   echo changed
  > fi
  unchanged
