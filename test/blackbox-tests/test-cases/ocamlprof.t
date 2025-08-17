Testing the ocamlprof profile.

  $ cat > dune-project <<EOF
  > (lang dune 3.21)
  > EOF

  $ cat > dune <<EOF
  > (executable
  >  (name foo))
  > EOF

  $ cat > foo.ml <<EOF
  > let f () = () ;;
  > let () = for i = 1 to 42 do f () done ;;
  > EOF

  $ dune exec --profile ocamlprof -- ./foo.exe

  $ ocamlprof foo.ml
  let f () = (* 42 *) () ;;
  let () = for i = 1 to 42 do f () done ;;

