open Stdune

let find_bin name =
  match Bin.which ~path:(Env_path.path Env.initial) name with
  | Some p -> Path.to_string p
  | None -> failwith (Printf.sprintf "binary not found: %s" name)
;;

let status_to_string = function
  | Unix.WEXITED n -> Printf.sprintf "WEXITED %d" n
  | Unix.WSIGNALED n -> Printf.sprintf "WSIGNALED %d" n
  | Unix.WSTOPPED n -> Printf.sprintf "WSTOPPED %d" n
;;

let%expect_test "echo traces paths" =
  let prog = find_bin "echo" in
  let status, paths =
    Spawn_with_trace.run ~prog ~argv:[| "echo" |] ~env:(Unix.environment ()) ()
  in
  Printf.printf "status: %s\n" (status_to_string status);
  Printf.printf "path count: %d\n" (List.length paths);
  [%expect
    {|
    status: WEXITED 0
    path count: 25
  |}]
;;

let%expect_test "cat traces /dev/null" =
  let prog = find_bin "cat" in
  let status, paths =
    Spawn_with_trace.run
      ~prog
      ~argv:[| "cat"; "/dev/null" |]
      ~env:(Unix.environment ())
      ()
  in
  Printf.printf "status: %s\n" (status_to_string status);
  List.iter
    ~f:(Printf.printf "%s\n")
    (List.filter ~f:(String.starts_with ~prefix:"/dev") paths);
  [%expect
    {|
    status: WEXITED 0
    /dev/null
  |}]
;;
