open Import

type kind =
  | Stubs of Foreign_stubs.t
  | Ctypes of Ctypes_field.t

type t =
  { kind : kind
  ; path : Path.Build.t
  ; language : Foreign_language.t
  }

let language t = t.language
let path t = t.path
let kind t = t.kind

let mode t =
  match t.kind with
  | Stubs { mode; _ } -> mode
  | Ctypes _ -> All
;;

let include_dirs t =
  match t.kind with
  | Stubs stubs -> stubs.include_dirs
  | Ctypes _ -> []
;;

let user_object_name t =
  t.path |> Path.Build.split_extension |> fst |> Path.Build.basename
;;

let add_mode_suffix mode s =
  match mode with
  | Mode.Select.All -> s
  | Only mode -> String.concat ~sep:"_" [ s; Mode.to_string mode ]
;;

let object_name t =
  user_object_name t
  |> Filename.to_string
  |> add_mode_suffix (mode t)
  |> Filename.of_string_exn
;;

let make kind ~path ~language = { kind; path; language }
