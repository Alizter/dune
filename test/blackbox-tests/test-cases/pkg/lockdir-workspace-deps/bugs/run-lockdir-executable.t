A workspace package runs an executable from a lockdir package while another
lockdir package depends on the workspace package:

consumer (lockdir) -> ws (workspace) -> tool (lockdir)

  $ make_lockdir
  $ make_lockpkg tool <<'EOF'
  > (version 0.0.1)
  > (install
  >  (system "mkdir -p %{bin} && printf '#!/bin/sh\necho from-tool\n' > %{bin}/tool && chmod +x %{bin}/tool"))
  > EOF

  $ make_dune_project 3.24
  $ cat >> dune-project <<EOF
  > (package
  >  (name ws)
  >  (depends tool))
  > EOF
  $ mkdir src
  $ cat > src/dune <<'EOF'
  > (rule
  >  (target generated)
  >  (action
  >   (with-stdout-to %{target}
  >    (run tool))))
  > (install
  >  (package ws)
  >  (section share)
  >  (files generated))
  > EOF

  $ make_lockpkg consumer <<EOF
  > (version 0.0.1)
  > (depends ws)
  > (build (run echo "building consumer"))
  > EOF
  $ write_lockdir_consumer_rule

Executable lookup evaluates consumer while building ws and closes a dependency
cycle:

  $ dune build out 2>&1 | censor
  Error: Dependency cycle between:
     _build/_private/default/.pkg/consumer.0.0.1-$DIGEST1/target/cookie
  -> Loading all binaries in the lock directory for "default"
  -> looking up binary "tool" in context "default"
  -> _build/default/src/generated
  -> _build/install/default/.packages/$DIGEST2/share/ws/generated
  -> _build/_private/default/.pkg/consumer.0.0.1-$DIGEST1/target/cookie
  -> required by _build/default/out
  [1]
