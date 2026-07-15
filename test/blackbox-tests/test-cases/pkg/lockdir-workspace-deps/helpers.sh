setup_workspace_fixture() {
  make_dune_project 3.24
  cat >> dune-project <<EOF
(package
 (name ws)
 (version 1.2.3))
EOF
  mkdir src
  cat > src/dune <<'EOF'
(library
 (name ws)
 (modules ws)
 (public_name ws))
(executable
 (name tool)
 (modules tool)
 (public_name ws-tool)
 (package ws))
(install
 (package ws)
 (section share)
 (files data))
EOF
  cat > src/ws.ml <<'EOF'
let greeting = "from-workspace-lib"
EOF
  cat > src/tool.ml <<'EOF'
let () = print_endline "from-workspace-exe"
EOF
  echo workspace-data > src/data
  make_lockdir
}

add_aux_workspace_fixture() {
  cat >> dune-project <<EOF
(package
 (name aux)
 (version 2.3.4))
EOF
  mkdir aux
  cat > aux/dune <<'EOF'
(library
 (name aux)
 (modules aux)
 (public_name aux))
(executable
 (name tool)
 (modules tool)
 (public_name aux-tool)
 (package aux))
(install
 (package aux)
 (section share)
 (files data))
EOF
  cat > aux/aux.ml <<'EOF'
let greeting = "from-aux-workspace-lib"
EOF
  cat > aux/tool.ml <<'EOF'
let () = print_endline "from-aux-workspace-exe"
EOF
  echo aux-workspace-data > aux/data
}

make_ws_depend_on_aux() {
  cat > dune-project <<EOF
(lang dune 3.24)
(package
 (name ws)
 (version 1.2.3)
 (depends aux))
(package
 (name aux)
 (version 2.3.4))
EOF
  cat > src/dune <<'EOF'
(library
 (name ws)
 (modules ws)
 (public_name ws)
 (libraries aux))
(executable
 (name tool)
 (modules tool)
 (public_name ws-tool)
 (package ws))
(install
 (package ws)
 (section share)
 (files data))
EOF
  cat > src/ws.ml <<'EOF'
let greeting = "from-workspace-lib:" ^ Aux.greeting
EOF
}

make_consumer() {
  local dependencies="$*"
  make_lockpkg consumer <<EOF
(version 0.0.1)
(depends $dependencies)
(build
 (progn
  (run ws-tool)
  (system "echo 'let () = print_endline Ws.greeting' > consumer.ml")
  (run ocamlfind ocamlc -package ws -linkpkg consumer.ml -o consumer.exe)
  (run ./consumer.exe)
  (system "test -f %{pkg:ws:share}/data && echo share-ok")
  (run echo %{pkg:ws:name})
  (run echo %{pkg:ws:version})
  (run echo %{pkg:ws:dev})))
EOF
  write_lockdir_consumer_rule
}

make_two_workspace_consumer() {
  local dependencies="$*"
  make_lockpkg consumer <<EOF
(version 0.0.1)
(depends $dependencies)
(build
 (progn
  (run ws-tool)
  (system "echo 'let () = print_endline Ws.greeting' > ws_consumer.ml")
  (run ocamlfind ocamlc -package ws -linkpkg ws_consumer.ml -o ws_consumer.exe)
  (run ./ws_consumer.exe)
  (system "test -f %{pkg:ws:share}/data && echo ws-share-ok")
  (run echo %{pkg:ws:version})
  (run aux-tool)
  (system "echo 'let () = print_endline Aux.greeting' > aux_consumer.ml")
  (run ocamlfind ocamlc -package aux -linkpkg aux_consumer.ml -o aux_consumer.exe)
  (run ./aux_consumer.exe)
  (system "test -f %{pkg:aux:share}/data && echo aux-share-ok")
  (run echo %{pkg:aux:version})))
EOF
  write_lockdir_consumer_rule
}

check_workspace_environment() {
  dune build out
}
