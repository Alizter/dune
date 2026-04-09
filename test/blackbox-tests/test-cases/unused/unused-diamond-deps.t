Diamond dependency: A depends on B and C, B and C both depend on D.
Exports of D used by B or C should not be reported as unused.

  $ cat > dune-project <<EOF
  > (lang dune 3.23)
  > EOF

  $ mkdir -p d c b a

  $ cat > d/dune <<EOF
  > (library
  >  (name d)
  >  (modules d))
  > EOF

  $ cat > d/d.ml <<EOF
  > let used_by_b x = x + 1
  > let used_by_c x = x * 2
  > let dead x = x - 1
  > EOF

  $ cat > d/d.mli <<EOF
  > val used_by_b : int -> int
  > val used_by_c : int -> int
  > val dead : int -> int
  > EOF

  $ cat > c/dune <<EOF
  > (library
  >  (name c)
  >  (modules c)
  >  (libraries d))
  > EOF

  $ cat > c/c.ml <<EOF
  > let value = D.used_by_c 1
  > EOF

  $ cat > c/c.mli <<EOF
  > val value : int
  > EOF

  $ cat > b/dune <<EOF
  > (library
  >  (name b)
  >  (modules b)
  >  (libraries d))
  > EOF

  $ cat > b/b.ml <<EOF
  > let value = D.used_by_b 1
  > EOF

  $ cat > b/b.mli <<EOF
  > val value : int
  > EOF

  $ cat > a/dune <<EOF
  > (executable
  >  (name main)
  >  (libraries b c))
  > EOF

  $ cat > a/main.ml <<EOF
  > let () = print_int (B.value + C.value)
  > EOF

Only D.dead should be reported. D.used_by_b and D.used_by_c are used
by B and C respectively:

  $ dune build @unused
  File "d/d.mli", line 3, characters 4-8:
  3 | val dead : int -> int
          ^^^^
  Error: unused export dead
  [1]
