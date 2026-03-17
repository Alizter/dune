Test that `and` and `or` in enabled_if use short-circuit evaluation.
Requires (lang dune 3.23) or higher.

  $ cat >dune-project <<EOF
  > (lang dune 3.23)
  > EOF

When the first conjunct of `and` is false, subsequent expressions are not evaluated:

  $ cat >dune <<EOF
  > (rule
  >  (alias foo)
  >  (enabled_if
  >   (and
  >    %{lib-available:nonexistent-library}
  >    (>= %{version:nonexistent-library} 1.0)))
  >  (action (echo "this should not run")))
  > EOF

  $ dune build @foo

When the first disjunct of `or` is true, subsequent expressions are not evaluated:

  $ cat >dune <<EOF
  > (rule
  >  (alias bar)
  >  (enabled_if
  >   (or
  >    %{lib-available:unix}
  >    (>= %{version:nonexistent-library} 1.0)))
  >  (action (echo "this should run")))
  > EOF

  $ dune build @bar
  this should run

Works with constant values too:

  $ cat >dune <<EOF
  > (rule
  >  (alias baz)
  >  (enabled_if
  >   (or
  >    true
  >    (>= %{version:nonexistent-library} 1.0)))
  >  (action (echo "constant short-circuit")))
  > EOF

  $ dune build @baz
  constant short-circuit
