A deprecated library name is owned by the package of its old public name and is
removed when that package is outside the scope.

  $ cat > dune-project <<'EOF'
  > (lang dune 3.22)
  > (using unreleased 0.1)
  > (package (name visible))
  > (package (name hidden))
  > EOF
  $ cat > dune <<'EOF'
  > (scope
  >  (packages visible))
  > (library
  >  (name visible)
  >  (public_name visible)
  >  (modules Visible))
  > (deprecated_library_name
  >  (old_public_name hidden)
  >  (new_public_name visible))
  > (executable
  >  (name main)
  >  (modules Main)
  >  (libraries hidden))
  > EOF
  $ echo 'let value = ()' > visible.ml
  $ echo 'let () = ()' > main.ml

  $ dune build ./main.exe 2> error
  [1]
  $ grep -F 'Library "hidden" not found' error
  Error: Library "hidden" not found.
