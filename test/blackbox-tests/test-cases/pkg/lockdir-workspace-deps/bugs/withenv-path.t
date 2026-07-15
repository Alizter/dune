A withenv update to PATH loses the workspace install layout.

  $ make_dune_project 3.24
  $ cat >> dune-project <<EOF
  > (package (name ws-tool))
  > EOF
  $ mkdir src
  $ cat > src/dune <<EOF
  > (executable
  >  (name main)
  >  (package ws-tool)
  >  (public_name foo))
  > EOF
  $ cat > src/main.ml <<EOF
  > let () = print_endline "from-workspace"
  > EOF

The lockdir also provides a binary named foo.

  $ make_lockdir
  $ make_lockpkg lock-tool <<'EOF'
  > (version 0.0.1)
  > (install
  >  (system "mkdir -p %{bin} && printf '#!/bin/sh\necho from-lockdir\n' > %{bin}/foo && chmod +x %{bin}/foo"))
  > EOF
  $ make_lockpkg consumer <<'EOF'
  > (version 0.0.1)
  > (depends lock-tool ws-tool)
  > (build
  >  (progn
  >   (system "foo > before-withenv.txt")
  >   (withenv
  >    ((+= PATH /unrelated))
  >    (system "foo > after-withenv.txt"))))
  > (install
  >  (system "mkdir -p %{share}/consumer && cp *-withenv.txt %{share}/consumer/"))
  > EOF
  $ write_lockdir_consumer_rule
  $ dune build out

The ordinary action finds the workspace binary, but withenv reconstructs PATH
without the workspace layout and falls back to the lockdir binary:

  $ find _build -name '*-withenv.txt' -exec cat {} \; | sort
  from-lockdir
  from-workspace
