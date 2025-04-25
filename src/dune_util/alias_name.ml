open Stdune
include String

module T = struct
  type t = string

  let module_ = "Alias_name"
  let description = "alias name"

  let description_of_valid_string =
    Pp.paragraph
      "Alias names must be non-empty and be different from '.' and '..'. They can \
       contain any non-whitespace character except for '/'."
    |> Option.some
  ;;

  (* TODO: *)
  let hint_valid = None

  (* Anything that doesn't look like a path is a valid alias name. *)
  let of_string_opt_loose s = Option.some_if (not @@ String.contains s '/') s

  let of_string_opt = function
    | "" | "." | "/" | ".." -> None
    | s -> of_string_opt_loose s
  ;;

  let to_string s = s
end

include T
include Stringlike.Make (T)

let to_dyn = String.to_dyn

let parse_local_path (loc, p) =
  match Path.Local.parent p with
  | Some dir -> dir, Path.Local.basename p
  | None ->
    User_error.raise
      ~loc
      [ Pp.textf "Invalid alias path: %S" (Path.Local.to_string_maybe_quoted p) ]
;;
