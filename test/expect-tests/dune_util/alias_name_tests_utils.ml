open Stdune
open Dune_util

let test_alias_name s =
  match Alias_name.of_string_opt s with
  | Some a -> a |> Alias_name.to_dyn |> Dyn.pp |> Format.printf "%a\n" Pp.to_fmt
  | None -> Printf.printf "Invalid alias name\n"
;;

let test_path s =
  match Alias_name.parse_local_path (Loc.none, Path.Local.of_string s) with
  | dir, name ->
    Printf.printf
      "✅ %s"
      (Dyn.record [ "dir", Path.Local.to_dyn dir; "alias_name", Alias_name.to_dyn name ]
       |> Dyn.to_string)
  | exception User_error.E e ->
    Printf.printf
      "❌ User error: %s\n"
      ({ e with paragraphs = [ List.hd e.paragraphs ] } |> User_message.to_string)
  | exception Code_error.E e ->
    Printf.printf "💀 Code error: %s\n" (Code_error.to_dyn_without_loc e |> Dyn.to_string)
;;
