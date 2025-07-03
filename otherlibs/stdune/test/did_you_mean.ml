open Stdune

let test s candidates =
  User_message.did_you_mean s ~candidates
  |> Pp.concat
  |> Pp.hovbox
  |> Format.printf "%a" Pp.to_fmt
;;

let%expect_test "did you mean" =
  test "acress" [ "caress" ];
  [%expect {| did you mean caress? |}];
  test "recievee" [ "receive" ];
  [%expect {| |}];
  test "rutnets" [ "runtest" ];
  [%expect {| |}];
  test "deffalt" [ "default" ];
  [%expect {| did you mean default? |}]
;;
