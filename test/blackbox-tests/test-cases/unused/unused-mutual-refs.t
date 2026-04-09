Mutually referencing modules with some dead exports.

  $ cat > dune-project <<EOF
  > (lang dune 3.23)
  > EOF

  $ cat > dune <<EOF
  > (executable
  >  (name main)
  >  (modules main a b))
  > EOF

  $ cat > main.ml <<EOF
  > let () = print_int (A.from_a 1)
  > EOF

A uses B.helper_b, B uses A.helper_a. Both also have dead exports.

  $ cat > a.ml <<EOF
  > let helper_a x = x + 1
  > let from_a x = B.helper_b (helper_a x)
  > let dead_a x = x * 3
  > EOF

  $ cat > a.mli <<EOF
  > val helper_a : int -> int
  > val from_a : int -> int
  > val dead_a : int -> int
  > EOF

  $ cat > b.ml <<EOF
  > let helper_b x = A.helper_a x + 1
  > let dead_b x = x - 1
  > EOF

  $ cat > b.mli <<EOF
  > val helper_b : int -> int
  > val dead_b : int -> int
  > EOF

helper_a, from_a, helper_b are all used cross-module.
dead_a and dead_b are unused:

  $ dune build @unused
  File "a.mli", line 3, characters 4-10:
  3 | val dead_a : int -> int
          ^^^^^^
  Error: unused export dead_a
  File "b.mli", line 2, characters 4-10:
  2 | val dead_b : int -> int
          ^^^^^^
  Error: unused export dead_b
  [1]
