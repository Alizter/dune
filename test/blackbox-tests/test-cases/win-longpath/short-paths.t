No warnings should appear when building with short paths, even with the
registry key "disabled".

  $ cat > dune-project <<EOF
  > (lang dune 3.0)
  > EOF

  $ cat > dune <<EOF
  > (executable (name main))
  > EOF

  $ cat > main.ml <<EOF
  > let () = print_endline "hello"
  > EOF

  $ DUNE_LONG_PATH_ENABLED=false dune build 2>&1 | sanitize_long_path_output
  
