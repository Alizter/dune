open Stdune

let _BUILD_PATH_PREFIX_MAP = "BUILD_PATH_PREFIX_MAP"

let extend_build_path_prefix_map env how map =
  let new_rules = Build_path_prefix_map.encode_map map in
  Env.update env ~var:_BUILD_PATH_PREFIX_MAP ~f:(function
    | None -> Some new_rules
    | Some existing_rules ->
      Some
        (match how with
         | `Existing_rules_have_precedence -> new_rules ^ ":" ^ existing_rules
         | `New_rules_have_precedence -> existing_rules ^ ":" ^ new_rules))
;;

(* On Windows, the same absolute path can appear in several forms in command
   output:
   - native forward slash:  C:/Users/...
   - native backslash:      C:\Users\...
   - cygwin / MSYS2:        /cygdrive/c/Users/...
   To match all of them, register extra prefix-map entries with the same
   target. [source] is assumed to be a drive-letter rooted path. *)
let win32_extra_entries ~source ~target =
  if not Sys.win32
  then []
  else (
    match source.[0], source.[1], source.[2] with
    | (('A' .. 'Z' | 'a' .. 'z') as letter), ':', ('/' | '\\') ->
      let rest = String.replace_char (String.drop source 2) ~from:'\\' ~to_:'/' in
      let backslash = String.replace_char source ~from:'/' ~to_:'\\' in
      let cygdrive = Printf.sprintf "/cygdrive/%c%s" (Char.lowercase_ascii letter) rest in
      [ Some { Build_path_prefix_map.source = backslash; target }
      ; Some { source = cygdrive; target }
      ]
    | _ -> []
    | exception Invalid_argument _ -> [])
;;
