open Stdune
include String

include Stringlike.Make (struct
    type t = string

    let module_ = "Alias_name"
    let description = "alias name"

    let description_of_valid_string =
      Pp.paragraph
        "Alias names must be non-empty (not \".\" or \"..\"), must not start with '@', \
         and may only contain non-whitespace characters excluding '/', '\\', '(' and \
         ')'."
      |> Option.some
    ;;

    (* TODO: *)
    let hint_valid = None

    let forbidden_characters =
      [ (* We don't use [Path.is_dir_sep] because we want to allow [':'] even on Windows.
           We have to do some clever parsing later. Forward and back slashes however seem
           like unsuitable characters for alias names. *)
        '/'
      ; '\\'
        (* Whitespace should be forbidden. The [Dune_lang] parser won't supply any, but
           there may be other routes we should check for. *)
      ; ' '
      ; '\t'
      ; '\n'
      ; '\r'
      ; '\012'
        (* We don't allow parentheses in alias names because they are used for grouping in
           S-expressions. *)
      ; '('
      ; ')'
      ]
    ;;

    (* On top of forbidden characters, we don't allow ['@'] at the start of an alias name
       since we use it for calling an [@alias] from the command line. *)
    let forbidden_first = [ '@' ] @ forbidden_characters

    (* Anything that doesn't look like a path is a valid alias name. *)
    let of_string_opt_loose s =
      Option.some_if
        ((* Checking the first character *)
         (not (List.exists ~f:(Char.equal (String.get s 0)) forbidden_first))
         (* Checking the rest *)
         && not (List.exists ~f:(String.contains_from s 1) forbidden_characters))
        s
    ;;

    let of_string_opt = function
      | "" | "." | ".." -> None
      | s -> of_string_opt_loose s
    ;;

    let to_string s = s
  end)

let to_dyn = String.to_dyn

let parse_local_path (loc, p) =
  match Path.Local.parent p with
  | Some dir -> dir, User_error.ok_exn @@ of_string_user_error (loc, Path.Local.basename p)
  | None ->
    User_error.raise
      ~loc
      [ Pp.textf "Invalid alias path: %S" (Path.Local.to_string_maybe_quoted p) ]
;;
