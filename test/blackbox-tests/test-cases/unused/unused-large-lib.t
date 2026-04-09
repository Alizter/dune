A larger wrapped public library with multiple modules. One module has
a genuinely unused export. Tests that the analysis works at scale.

  $ cat > dune-project <<EOF
  > (lang dune 3.23)
  > (package (name mypkg))
  > EOF

  $ cat > dune <<EOF
  > (library
  >  (name mylib)
  >  (public_name mypkg.mylib)
  >  (root_module root)
  >  (modules root utils path fpath))
  > EOF

  $ cat > root.ml <<EOF
  > module Utils = Utils
  > module Path = Path
  > module Fpath = Fpath
  > EOF

  $ cat > root.mli <<EOF
  > module Utils = Utils
  > module Path = Path
  > module Fpath = Fpath
  > EOF

  $ cat > utils.ml <<EOF
  > let helper x = x + 1
  > let dead_util x = x * 3
  > let used_by_path x = x + 2
  > EOF

  $ cat > utils.mli <<EOF
  > val helper : int -> int
  > val dead_util : int -> int
  > val used_by_path : int -> int
  > EOF

  $ cat > path.ml <<EOF
  > let join a b = a ^ "/" ^ b
  > let normalize x = x
  > let using_utils x = Utils.used_by_path x
  > EOF

  $ cat > path.mli <<EOF
  > val join : string -> string -> string
  > val normalize : string -> string
  > val using_utils : int -> int
  > EOF

  $ cat > fpath.ml <<EOF
  > let follow_symlinks x = Some x
  > let resolve x = x
  > EOF

  $ cat > fpath.mli <<EOF
  > val follow_symlinks : string -> string option
  > val resolve : string -> string
  > EOF

used_by_path is used by path.ml (cross-module reference within the lib).
The rest are unused. used_by_path should NOT be reported:

  $ dune build @unused
  File "fpath.mli", line 1, characters 4-19:
  1 | val follow_symlinks : string -> string option
          ^^^^^^^^^^^^^^^
  Error: unused export follow_symlinks
  File "fpath.mli", line 2, characters 4-11:
  2 | val resolve : string -> string
          ^^^^^^^
  Error: unused export resolve
  File "path.mli", line 1, characters 4-8:
  1 | val join : string -> string -> string
          ^^^^
  Error: unused export join
  File "path.mli", line 2, characters 4-13:
  2 | val normalize : string -> string
          ^^^^^^^^^
  Error: unused export normalize
  File "path.mli", line 3, characters 4-15:
  3 | val using_utils : int -> int
          ^^^^^^^^^^^
  Error: unused export using_utils
  File "utils.mli", line 1, characters 4-10:
  1 | val helper : int -> int
          ^^^^^^
  Error: unused export helper
  File "utils.mli", line 2, characters 4-13:
  2 | val dead_util : int -> int
          ^^^^^^^^^
  Error: unused export dead_util
  [1]
