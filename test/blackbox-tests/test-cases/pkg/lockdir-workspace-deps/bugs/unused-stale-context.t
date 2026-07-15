An out-of-sync lockdir in an unused context blocks a build in another,
explicitly requested context.

  $ cat > dune-workspace <<EOF
  > (lang dune 3.24)
  > (context
  >  (default
  >   (lock_dir good.lock)))
  > (context
  >  (default
  >   (name stale)
  >   (lock_dir stale.lock)))
  > EOF
  $ cat > dune-project <<EOF
  > (lang dune 3.24)
  > (package
  >  (name x)
  >  (allow_empty))
  > EOF
  $ mkdir good.lock
  $ cat > good.lock/lock.dune <<EOF
  > (lang package 0.1)
  > EOF
  $ mkdir stale.lock
  $ cat > stale.lock/lock.dune <<EOF
  > (lang package 0.1)
  > (dependency_hash 00000000000000000000000000000000)
  > EOF
  $ cat > dune <<EOF
  > (rule
  >  (target out)
  >  (action (with-stdout-to %{target} (echo ok))))
  > EOF

  $ dune build _build/default/out
  File "stale.lock/lock.dune", line 1, characters 0-0:
  Error: The lock dir is not sync with your dune-project
  Hint: run dune pkg lock
  [1]
