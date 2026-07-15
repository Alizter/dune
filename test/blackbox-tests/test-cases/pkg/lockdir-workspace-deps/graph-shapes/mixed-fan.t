Mixed fan: consumer (L) -> provider (L) and ws (W). Provider installs an
executable with the same name; the workspace executable retains precedence.

  $ setup_workspace_fixture
  $ make_lockpkg provider <<'EOF'
  > (version 0.0.1)
  > (install
  >  (system "mkdir -p %{bin} && printf '#!/bin/sh\necho from-lockdir-exe\n' > %{bin}/ws-tool && chmod +x %{bin}/ws-tool"))
  > EOF
  $ make_consumer provider ws
  $ check_workspace_environment
  from-workspace-exe
  from-workspace-lib
  share-ok
  ws
  1.2.3
  false
