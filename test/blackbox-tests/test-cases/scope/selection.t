Scope filtering happens before duplicate package detection. Exactly one of two
packages with the same name can therefore be selected.

  $ cat > dune-project <<'EOF'
  > (lang dune 3.22)
  > (using unreleased 0.1)
  > (package (name app))
  > EOF
  $ cat > dune <<'EOF'
  > (executable
  >  (name main)
  >  (libraries choice))
  > EOF
  $ cat > main.ml <<'EOF'
  > let () = print_endline Choice.message
  > EOF

  $ mkdir selected hidden
  $ cat > selected/dune-project <<'EOF'
  > (lang dune 3.22)
  > (using unreleased 0.1)
  > (package (name choice))
  > EOF
  $ cat > selected/dune <<'EOF'
  > (scope
  >  (packages choice))
  > (library
  >  (name choice)
  >  (public_name choice))
  > EOF
  $ echo 'let message = "selected choice"' > selected/choice.ml

An empty package set hides every package defined beneath the scope.

  $ cat > hidden/dune-project <<'EOF'
  > (lang dune 3.22)
  > (using unreleased 0.1)
  > (package (name choice))
  > EOF
  $ cat > hidden/dune <<'EOF'
  > (scope
  >  (packages))
  > (library
  >  (name choice)
  >  (public_name choice))
  > EOF
  $ echo 'let message = "hidden choice"' > hidden/choice.ml

  $ dune exec ./main.exe
  selected choice
