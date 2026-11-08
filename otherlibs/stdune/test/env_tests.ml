open Stdune

let a = Env.Var.of_string "A"
let b = Env.Var.of_string "B"

let%expect_test "environment variable names cannot contain NUL bytes" =
  (match Env.Var.of_string "A\000B" with
   | _ -> print_endline "accepted"
   | exception Code_error.E _ -> print_endline "rejected");
  [%expect {| rejected |}]
;;

let find_assignment env var =
  Env.to_unix env
  |> List.find_map ~f:(fun assignment ->
    match String.lsplit2 assignment ~on:'=' with
    | Some (key, _) when String.equal key var -> Some assignment
    | Some _ | None -> None)
  |> Option.value_exn
;;

let%expect_test "updating a binding preserves the others" =
  let env = Env.empty |> Env.add ~var:a ~value:"one" |> Env.add ~var:b ~value:"two" in
  let updated = Env.add env ~var:b ~value:"three" in
  print_endline (find_assignment updated "A");
  print_endline (find_assignment updated "B");
  [%expect
    {|
    A=one
    B=three |}]
;;

let%expect_test "rendering preserves the environment hash" =
  let env = Env.empty |> Env.add ~var:a ~value:"one" in
  let before = Env.hash env in
  ignore (Env.to_unix env);
  print_endline (Bool.to_string (Int.equal before (Env.hash env)));
  [%expect {| true |}]
;;

let%expect_test "environment values reject NUL bytes when added" =
  (match Env.add Env.empty ~var:a ~value:"value\000" with
   | exception Code_error.E _ -> print_endline "rejected"
   | _ -> print_endline "accepted");
  [%expect {| rejected |}]
;;

let%expect_test "setting an unchanged variable reuses the environment" =
  let env = Env.empty |> Env.add ~var:a ~value:"one" in
  let unchanged = Env.add env ~var:a ~value:"one" in
  let changed = Env.add env ~var:a ~value:"two" in
  print_endline (Bool.to_string (env == unchanged));
  print_endline (Bool.to_string (env == changed));
  [%expect
    {|
    true
    false |}]
;;

let path_dir path = Path.Build.of_local (Path.Local.of_string path)

let print_local_bin_dirs env =
  Env.local_bin_dirs env
  |> List.map ~f:(fun path -> Path.Build.local path |> Path.Local.to_string)
  |> String.concat ~sep:","
  |> print_endline
;;

let%expect_test "Scoped binary directories survive environment composition" =
  let first =
    Env.add_local_bin_dirs
      (Env.add Env.empty ~var:a ~value:"one")
      [ path_dir "default/.bin" ]
  in
  let second =
    Env.add_local_bin_dirs
      (Env.add Env.empty ~var:b ~value:"two")
      [ path_dir "default/nested/.bin" ]
  in
  let combined = Env.extend_env first second in
  List.iter [ first; second; combined; Env.diff combined first ] ~f:print_local_bin_dirs;
  [%expect
    {|
    default/.bin
    default/nested/.bin
    default/.bin,default/nested/.bin
    default/nested/.bin |}]
;;

let%expect_test "Scoped binary directory metadata survives binding replacement" =
  let env =
    Env.add_local_bin_dirs
      (Env.add Env.empty ~var:Env_path.var ~value:"/literal")
      [ path_dir "default/.bin" ]
  in
  let removed = Env.remove env ~var:Env_path.var in
  print_endline (Bool.to_string (Env.is_empty removed));
  print_endline (Bool.to_string (List.is_empty (Env.to_unix removed)));
  let restored = Env.add removed ~var:Env_path.var ~value:"" in
  print_local_bin_dirs restored;
  print_endline (find_assignment restored "PATH");
  [%expect
    {|
    false
    true
    default/.bin
    PATH= |}]
;;

let%expect_test "Scoped binary directory metadata participates in equality and hashing" =
  let plain = Env.add Env.empty ~var:a ~value:"one" in
  let dir = path_dir "default/.bin" in
  let registered = Env.add_local_bin_dirs plain [ dir ] in
  let repeated = Env.add_local_bin_dirs registered [ dir; dir ] in
  print_endline (Bool.to_string (Env.equal plain registered));
  print_endline (Bool.to_string (Env.equal registered repeated));
  print_endline (Bool.to_string (Int.equal (Env.hash registered) (Env.hash repeated)));
  print_endline (Bool.to_string (Int.equal (Env.hash plain) (Env.hash registered)));
  print_endline (Bool.to_string (Env.to_unix plain = Env.to_unix registered));
  [%expect
    {|
    false
    true
    true
    false
    true |}]
;;
