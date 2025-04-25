open Stdune
open Dune_util.Alias_name

let invalid_alias = Pp.textf "%S is not a valid alias name"

let decode =
  let parse_string_exn (loc, s) =
    match of_string_opt s with
    | None -> User_error.raise ~loc [ invalid_alias s ]
    | Some s -> s
  in
  let open Dune_sexp.Decoder in
  plain_string (fun ~loc s -> parse_string_exn (loc, s))
;;
