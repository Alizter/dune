open Stdune

let%expect_test "empty list" =
  [] |> Hlist.to_dyn [] |> Dyn.to_string |> print_endline;
  [%expect {| [] |}]
;;

let%expect_test "singleton list" =
  [ 1 ] |> Hlist.to_dyn [ Dyn.int ] |> Dyn.to_string |> print_endline;
  [%expect {| [ 1 ] |}]
;;

let%expect_test "pair list" =
  [ 1; 2. ] |> Hlist.to_dyn [ Dyn.int; Dyn.float ] |> Dyn.to_string |> print_endline;
  [%expect {| [ 1; 2. ] |}]
;;

let%expect_test "triple list" =
  [ 1; 2.; "3" ]
  |> Hlist.to_dyn [ Dyn.int; Dyn.float; Dyn.string ]
  |> Dyn.to_string
  |> print_endline;
  [%expect {| [ 1; 2.; "3" ] |}]
;;

(* let%expect_test "invalid list" =
   Hlist.apply [ Dyn.int; Dyn.int; Dyn.int ] [ 1; 2; 3 ]
   |> Hlist.to_triple
   |> Dyn.triple
   |> Dyn.to_string
   |> print_endline;
   [%expect {| [ 1; 4119892; 4119664 ] |}]
   ;; *)
