open! Stdune

let unquote_string s = String.sub s ~pos:1 ~len:(String.length s - 2)

let get_unquoted_vfile lexbuf =
  let s = Lexing.lexeme lexbuf in
  let f = unquote_string s in
  if Filename.check_suffix f ".v" then Filename.chop_suffix f ".v" else f

let backtrack lexbuf =
  let open Lexing in
  lexbuf.lex_curr_pos <- lexbuf.lex_start_pos;
  lexbuf.lex_curr_p <- lexbuf.lex_start_p

let syntax_error ~who ?desc ?hint lexbuf =
  let loc = Loc.of_lexbuf lexbuf in
  let desc =
    match desc with
    | None -> []
    | Some desc -> [ Pp.text desc ]
  in
  let who = [ Pp.text who ] in
  let hints = Option.map ~f:(fun x -> [ Pp.text x ]) hint in
  User_error.raise ~loc ?hints
    (Pp.[ text "Syntax error during lexing." ] @ desc @ who)

(* raise (Syntax_error Metadata.{ hint; who; desc; loc; file }) *)

let get_module ?(quoted = false) lexbuf =
  let logical_name =
    if quoted then Lexing.lexeme lexbuf |> unquote_string
    else Lexing.lexeme lexbuf
  in
  Token.Module.make (Loc.of_lexbuf lexbuf) logical_name

(* Some standard error descriptions *)
let msg_eof = "File ended unexpectedly."

let msg_unable lexbuf =
  Printf.sprintf "Unable to parse: \"%s\"." (Lexing.lexeme lexbuf)

let hint_eof_term = "Did you forget a \".\"?"
