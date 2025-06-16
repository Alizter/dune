open Stdune

let () = Dune_tests_common.init ()

(* Basic example adding and removing a line. *)
let basic =
  {|
diff --git a/foo.ml b/foo.ml
index b69a69a5a..ea988f6bd 100644
--- a/foo.ml
+++ b/foo.ml
@@ -1,1 +1,1 @@
-This is wrong
+This is right
|}
;;

(* Example adding and removing a line in a file in a subdirectory. *)
let subdirectory =
  {|
diff --git a/dir/foo.ml b/dir/foo.ml
index b69a69a5a..ea988f6bd 100644
--- a/dir/foo.ml
+++ b/dir/foo.ml
@@ -1,1 +1,1 @@
-This is wrong
+This is right
|}
;;

(* Previous two example combined into a single patch. *)
let combined = String.concat ~sep:"\n" [ basic; subdirectory ]

(* Example adding a new file. *)
let new_file =
  {|
diff --git a/foo.ml b/foo.ml
new file mode 100644
index 000000000..ea988f6bd
--- /dev/null
+++ b/foo.ml
@@ -0,0 +1,2 @@
+This is right
+
|}
;;

(* Example deleting an existing file. *)
let delete_file =
  {|
diff --git a/foo.ml b/foo.ml
deleted file mode 100644
index ea988f6bd..000000000
--- a/foo.ml
+++ /dev/null
@@ -1,1 +0,0 @@
-This is wrong
|}
;;

(* Use GNU diff 'unified' format instead of 'git diff' *)
let unified =
  {|
diff -u a/foo.ml b/foo.ml
--- a/foo.ml	2024-08-29 17:37:53.114980665 +0200
+++ b/foo.ml	2024-08-29 17:38:00.243088256 +0200
@@ -1 +1 @@
-This is wrong
+This is right
|}
;;

let no_prefix =
  {|
--- foo.ml	2024-08-29 17:37:53.114980665 +0200
+++ foo.ml	2024-08-29 17:38:00.243088256 +0200
@@ -1 +1 @@
-This is wrong
+This is right
|}
;;

let random_prefix =
  {|
diff -u bar/foo.ml baz/foo.ml
--- bar/foo.ml	2024-08-29 17:37:53.114980665 +0200
+++ baz/foo.ml	2024-08-29 17:38:00.243088256 +0200
@@ -1 +1 @@
-This is wrong
+This is right
|}
;;

(* The file is called "foo bar" *)
let spaces =
  {|
diff --git a/foo bar b/foo bar
index ef00db3..88adca3 100644
--- a/foo bar   
+++ b/foo bar   
@@ -1 +1 @@
-This is wrong.
+This is right.
|}
;;

(* The file is called "foo bar" but in unified diff its quoted *)
let unified_spaces =
  {|
--- "a/foo bar"	2024-09-04 10:56:24.139293679 +0200
+++ "b/foo bar"	2024-09-04 10:56:12.519195763 +0200
@@ -1 +1 @@
-This is wrong.
+This is right.
|}
;;

let hello_world =
  {|
diff --git a/foo.ml b/foo.ml
new file mode 100644
index 0000000..557db03
--- /dev/null
+++ b/foo.ml
@@ -0,0 +1 @@
+Hello World
|}
;;

(* Testing patch prefix parsing *)

let test p =
  Dune_patch.For_tests.prefix_of_patch ~loc:Loc.none p |> Printf.printf "prefix: %d"
;;

let%expect_test "patch prefix" =
  test basic;
  [%expect {| prefix: 1 |}];
  test subdirectory;
  [%expect {| prefix: 1 |}];
  test combined;
  [%expect {| prefix: 1 |}];
  test no_prefix;
  [%expect {| prefix: 0 |}];
  test random_prefix;
  [%expect {| prefix: 1 |}];
  test unified_spaces;
  [%expect {| prefix: 1 |}]
;;

(* Testing patch parsing *)

let git_ext_to_dyn = function
  | _ -> assert false
;;

let operation_to_dyn = function
  | Patch.Edit (mine, their) -> Dyn.variant "Edit" [ Dyn.string mine; Dyn.string their ]
  | Delete mine -> Dyn.variant "Delete" [ Dyn.string mine ]
  | Create their -> Dyn.variant "Create" [ Dyn.string their ]
  | Git_ext (mine, their, git_ext) ->
    Dyn.variant "Git_ext" [ Dyn.string mine; Dyn.string their; git_ext_to_dyn git_ext ]
;;

let hunk_to_dyn { Patch.mine_start; mine_len; mine; their_start; their_len; their } =
  Dyn.record
    [ "mine_start", Dyn.int mine_start
    ; "mine_len", Dyn.int mine_len
    ; "mine", Dyn.list Dyn.string mine
    ; "their_start", Dyn.int their_start
    ; "their_len", Dyn.int their_len
    ; "their", Dyn.list Dyn.string their
    ]
;;

let patch_to_dyn { Patch.operation; hunks; mine_no_nl; their_no_nl } =
  Dyn.record
    [ "operation", operation_to_dyn operation
    ; "hunks", Dyn.list hunk_to_dyn hunks
    ; "mine_no_nl", Dyn.bool mine_no_nl
    ; "their_no_nl", Dyn.bool their_no_nl
    ]
;;

let test p =
  Dune_patch.For_tests.parse_patches ~loc:Loc.none p
  |> Dyn.list patch_to_dyn
  |> Dyn.pp
  |> Format.printf "%a" Pp.to_fmt
;;

let%expect_test "parse basic patch" =
  test basic;
  [%expect
    {|
    [ { operation = Edit ("foo.ml", "foo.ml")
      ; hunks =
          [ { mine_start = 1
            ; mine_len = 1
            ; mine = [ "This is wrong" ]
            ; their_start = 1
            ; their_len = 1
            ; their = [ "This is right" ]
            }
          ]
      ; mine_no_nl = false
      ; their_no_nl = false
      }
    ]
    |}]
;;

let%expect_test "parse subdirectory patch" =
  test subdirectory;
  [%expect
    {|
    [ { operation = Edit ("dir/foo.ml", "dir/foo.ml")
      ; hunks =
          [ { mine_start = 1
            ; mine_len = 1
            ; mine = [ "This is wrong" ]
            ; their_start = 1
            ; their_len = 1
            ; their = [ "This is right" ]
            }
          ]
      ; mine_no_nl = false
      ; their_no_nl = false
      }
    ]
    |}]
;;

let%expect_test "parse combined patch" =
  test combined;
  [%expect
    {|
    [ { operation = Edit ("foo.ml", "foo.ml")
      ; hunks =
          [ { mine_start = 1
            ; mine_len = 1
            ; mine = [ "This is wrong" ]
            ; their_start = 1
            ; their_len = 1
            ; their = [ "This is right" ]
            }
          ]
      ; mine_no_nl = false
      ; their_no_nl = false
      }
    ; { operation = Edit ("dir/foo.ml", "dir/foo.ml")
      ; hunks =
          [ { mine_start = 1
            ; mine_len = 1
            ; mine = [ "This is wrong" ]
            ; their_start = 1
            ; their_len = 1
            ; their = [ "This is right" ]
            }
          ]
      ; mine_no_nl = false
      ; their_no_nl = false
      }
    ]
    |}]
;;

let%expect_test "parse new_file patch" =
  test new_file;
  [%expect
    {|
    [ { operation = Create "foo.ml"
      ; hunks =
          [ { mine_start = 0
            ; mine_len = 0
            ; mine = []
            ; their_start = 1
            ; their_len = 2
            ; their = [ "This is right"; "" ]
            }
          ]
      ; mine_no_nl = false
      ; their_no_nl = false
      }
    ]
    |}]
;;

let%expect_test "parse delete_file patch" =
  test delete_file;
  [%expect
    {|
    [ { operation = Delete "foo.ml"
      ; hunks =
          [ { mine_start = 1
            ; mine_len = 1
            ; mine = [ "This is wrong" ]
            ; their_start = 0
            ; their_len = 0
            ; their = []
            }
          ]
      ; mine_no_nl = false
      ; their_no_nl = false
      }
    ]
    |}]
;;

let%expect_test "parse unified patch" =
  test unified;
  [%expect
    {|
    [ { operation = Edit ("foo.ml", "foo.ml")
      ; hunks =
          [ { mine_start = 1
            ; mine_len = 1
            ; mine = [ "This is wrong" ]
            ; their_start = 1
            ; their_len = 1
            ; their = [ "This is right" ]
            }
          ]
      ; mine_no_nl = false
      ; their_no_nl = false
      }
    ]
    |}]
;;

let%expect_test "parse no_prefix patch" =
  test no_prefix;
  [%expect
    {|
    [ { operation = Edit ("foo.ml", "foo.ml")
      ; hunks =
          [ { mine_start = 1
            ; mine_len = 1
            ; mine = [ "This is wrong" ]
            ; their_start = 1
            ; their_len = 1
            ; their = [ "This is right" ]
            }
          ]
      ; mine_no_nl = false
      ; their_no_nl = false
      }
    ]
    |}]
;;

let%expect_test "parse random_prefix patch" =
  test random_prefix;
  [%expect
    {|
    [ { operation = Edit ("foo.ml", "foo.ml")
      ; hunks =
          [ { mine_start = 1
            ; mine_len = 1
            ; mine = [ "This is wrong" ]
            ; their_start = 1
            ; their_len = 1
            ; their = [ "This is right" ]
            }
          ]
      ; mine_no_nl = false
      ; their_no_nl = false
      }
    ]
    |}]
;;

let%expect_test "parse spaces patch" =
  test spaces;
  [%expect
    {|
    [ { operation = Edit ("foo", "foo")
      ; hunks =
          [ { mine_start = 1
            ; mine_len = 1
            ; mine = [ "This is wrong." ]
            ; their_start = 1
            ; their_len = 1
            ; their = [ "This is right." ]
            }
          ]
      ; mine_no_nl = false
      ; their_no_nl = false
      }
    ]
    |}]
;;

let%expect_test "parse unified_spaces patch`" =
  test unified_spaces;
  [%expect
    {|
    [ { operation = Edit ("foo bar", "foo bar")
      ; hunks =
          [ { mine_start = 1
            ; mine_len = 1
            ; mine = [ "This is wrong." ]
            ; their_start = 1
            ; their_len = 1
            ; their = [ "This is right." ]
            }
          ]
      ; mine_no_nl = false
      ; their_no_nl = false
      }
    ]
|}]
;;

let%expect_test "parse hello_world patch" =
  test hello_world;
  [%expect
    {|
    [ { operation = Create "foo.ml"
      ; hunks =
          [ { mine_start = 0
            ; mine_len = 0
            ; mine = []
            ; their_start = 1
            ; their_len = 1
            ; their = [ "Hello World" ]
            }
          ]
      ; mine_no_nl = false
      ; their_no_nl = false
      }
    ]
    |}]
;;

(* Testing parsing of bad patch names *)

let bad_name name =
  {|
--- /dev/null
+++ |}
  ^ name
  ^ {|
@@ -0,0 +1 @@
+x
|}
;;

let test name =
  let loc = Loc.in_file (Path.of_string "dummy.file") in
  match Dune_patch.For_tests.parse_patches ~loc (bad_name name) with
  | exception e -> Exn.pp e |> Format.printf "%a" Pp.to_fmt
  | _ -> print_endline "No error!"
;;

let%expect_test "forbid current dir" =
  (* We don't allow "." *)
  test ".";
  [%expect
    {|
    File "dummy.file", line 1, characters 0-0:
    Error: Directory "." in patch file is
    invalid.
  |}]
;;

let%expect_test "bad patch names" =
  (* We wish to reject all patches beginning with "..". *)
  (* TODO: error message a little funny here. *)
  test "../a";
  [%expect
    {|
    File "dummy.file", line 1, characters 0-0:
    Error: path outside the workspace: ../a from
    .
    |}]
;;

let%expect_test "allow parent dir in subdir" =
  (* This is fine, since Dune is able to understand the path. *)
  test "a/../b";
  [%expect {| No error! |}]
;;

let%expect_test "_" =
  test "a/..";
  [%expect {|
    File "dummy.file", line 1, characters 0-0:
    Error: Directory "a/.." in patch file is
    invalid.
    |}]
;;

let%expect_test "forbid absolute dirs" =
  (* TODO: raise user error *)
  test "/a";
  [%expect
    {|
    ("Local.relative: received absolute path", { t = "."; path = "/a"
    })
  |}]
;;

(* Testing patch applicaiton *)


(* Testing the patch action *)

include struct
  open Dune_engine
  module Action = Action
  module Display = Display
  module Process = Process
  module Scheduler = Scheduler
end

let create_files =
  List.iter ~f:(fun (f, contents) ->
    ignore
      (Fpath.mkdir_p
         (Path.Local.of_string f
          |> Path.Local.parent
          |> Option.value ~default:(Path.Local.of_string ".")
          |> Path.Local.to_string));
    Io.String_path.write_file f contents)
;;

let test files (patch, patch_contents) =
  let dir = Temp.create Dir ~prefix:"dune" ~suffix:"patch_test" in
  Sys.chdir (Path.to_string dir);
  let patch_file = Path.append_local dir (Path.Local.of_string patch) in
  let config =
    { Scheduler.Config.concurrency = 1
    ; stats = None
    ; print_ctrl_c_warning = false
    ; watch_exclusions = []
    }
  in
  Scheduler.Run.go
    config
    ~timeout_seconds:5.0
    ~file_watcher:No_watcher
    ~on_event:(fun _ _ -> ())
  @@ fun () ->
  let open Fiber.O in
  let* () = Fiber.return @@ create_files ((patch, patch_contents) :: files) in
  Dune_patch.For_tests.exec
    ~loc:(Loc.in_file (Path.of_string "dune.patch.test"))
    ~patch:patch_file
    ~dir
;;

let check path =
  match (Unix.stat path).st_kind with
  | S_REG -> Io.String_path.cat path
  | _ -> failwith "Not a regular file"
  | exception Unix.Unix_error (Unix.ENOENT, _, _) -> printfn "File %s not found" path
;;

let%expect_test "patching a file" =
  test [ "foo.ml", "This is wrong\n" ] ("foo.patch", basic);
  check "foo.ml";
  [%expect
    {|
    This is right |}]
;;

let%expect_test "patching a file in a subdirectory" =
  test [ "dir/foo.ml", "This is wrong\n" ] ("foo.patch", subdirectory);
  check "dir/foo.ml";
  [%expect
    {|
    This is right |}]
;;

let%expect_test "patching two files with a single patch" =
  test
    [ "foo.ml", "This is wrong\n"; "dir/foo.ml", "This is wrong\n" ]
    ("foo.patch", combined);
  check "foo.ml";
  [%expect
    {|
    This is right |}]
;;

let%expect_test "patching a new file" =
  test [] ("foo.patch", new_file);
  check "foo.ml";
  [%expect
    {|
    This is right |}]
;;

let () = Dune_util.Report_error.report_backtraces true

let%expect_test "patching a deleted file" =
  let filename = "foo.ml" in
  test [ filename, "This is wrong\n" ] ("foo.patch", delete_file);
  match Unix.stat filename with
  | _ -> failwith "Still exists"
  | exception Unix.Unix_error (Unix.ENOENT, _, _) -> ()
;;

let undo_breaks =
  String.map ~f:(function
    | '\n' -> ' '
    | c -> c)
;;

let rsplit2_exn s ~on =
  match String.rsplit2 s ~on with
  | Some s -> s
  | None -> Code_error.raise "rsplit2_exn" [ "s", String s; "on", Char on ]
;;

let normalize_error_path s =
  let s = undo_breaks s in
  let location, reason = rsplit2_exn s ~on:':' in
  let prefix, path = String.lsplit2_exn location ~on:' ' in
  let path = Filename.basename path in
  sprintf "%s %s:%s" prefix path reason
;;

let%expect_test "Using a patch from 'diff' with a timestamp" =
  test [ "foo.ml", "This is wrong\n" ] ("foo.patch", unified);
  check "foo.ml";
  [%expect
    {|
    This is right |}]
;;

let%expect_test "patching a file without prefix" =
  test [ "foo.ml", "This is wrong\n" ] ("foo.patch", no_prefix);
  check "foo.ml";
  [%expect {| This is right |}]
;;

let%expect_test "patching files with freestyle prefix" =
  test [ "foo.ml", "This is wrong\n" ] ("foo.patch", random_prefix);
  check "foo.ml";
  [%expect {| This is right |}]
;;

let%expect_test "patching files with spaces" =
  try
    test [ "foo bar", "This is wrong\n" ] ("foo.patch", spaces);
    check "foo bar";
    [%expect.unreachable]
  with
  | Dune_util.Report_error.Already_reported ->
    print_endline @@ normalize_error_path [%expect.output];
    [%expect {| Error: foo): No such file or directory |}]
;;

let%expect_test "patching files with (unified) spaces" =
  try
    test [ "foo bar", "This is wrong\n" ] ("foo.patch", unified_spaces);
    check "foo bar";
    [%expect.unreachable]
  with
  | Dune_util.Report_error.Already_reported ->
    print_endline [%expect.output];
    [%expect
      {|
      Error: exception Invalid_argument("apply_hunk")

      I must not crash.  Uncertainty is the mind-killer. Exceptions are the
      little-death that brings total obliteration.  I will fully express my cases.
      Execution will pass over me and through me.  And when it has gone past, I
      will unwind the stack along its path.  Where the cases are handled there will
      be nothing.  Only I will remain.
      |}]
;;
