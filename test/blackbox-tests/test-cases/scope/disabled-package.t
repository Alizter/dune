A scope does not enable a package disabled by its enabled_if condition.

  $ cat > dune-project <<'EOF'
  > (lang dune 3.22)
  > (using unreleased 0.1)
  > (package
  >  (name disabled)
  >  (enabled_if false))
  > EOF
  $ cat > dune <<'EOF'
  > (scope
  >  (packages disabled))
  > (library
  >  (name disabled)
  >  (public_name disabled))
  > (executable
  >  (name main)
  >  (libraries disabled))
  > EOF
  $ echo 'let value = ()' > disabled.ml
  $ echo 'let () = ()' > main.ml

  $ dune build ./main.exe 2> error
  [1]
  $ grep -F 'Library "disabled" not found' error
  Error: Library "disabled" not found.
