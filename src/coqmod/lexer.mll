{
  open! Stdune
  open Util
  exception End_of_file
}

let whitespace = [' ' '\t' '\r']
let newline = '\n'
let quoted = '"' [^ '"']* '"'

let coq_ident_start_char = ['A'-'Z' 'a'-'z' '_' '\128'-'\255']
let coq_ident_char = ['A'-'Z' 'a'-'z' '_' '\'' '0'-'9' '\128'-'\255']
let coq_ident = coq_ident_start_char coq_ident_char*
let coq_field = '.' coq_ident
let coq_qualid = coq_ident coq_field*
let coq_qid_quot = '"' coq_qualid '"'

let locality = "Local" | "Global" | "#[local]" | "#[global]"

let comment_begin = "(*"
let comment_end = "*)"

rule parse_coq t = parse
  (* All newlines must be manually processed in order to have good locations *)
  | newline       { Lexing.new_line lexbuf; parse_coq t lexbuf }
  | whitespace+   { parse_coq t lexbuf }
  | comment_begin { parse_comment lexbuf; parse_coq t lexbuf }
  | eof           { raise End_of_file }
  (* Noops - These are ignored on purpose *)
  | locality      { parse_coq t lexbuf }
  | "Time"        { parse_coq t lexbuf }
  | "Timeout"     { parse_timeout t lexbuf }
  | "Comments"    { parse_vernac_comments t lexbuf }
  (* Entry points to more sophisticated parsing *)
  | "Declare"     { parse_declare t lexbuf }
  | "Load"        { parse_load t lexbuf }
  | "Require"     { parse_require_modifiers t None lexbuf }
  | "From"        { parse_from t lexbuf }
  (* Everything else *)
  | _             { skip_to_dot t lexbuf; parse_coq t lexbuf }

(* Parsing comments *)
and parse_comment = parse
  | newline       { Lexing.new_line lexbuf; parse_comment lexbuf }
  | comment_begin { parse_comment lexbuf; parse_comment lexbuf }
  | comment_end   { () }
  | eof           { raise End_of_file }
  | _             { parse_comment lexbuf }

(* Rule for fast forwarding to a dot, skipping most things. *)
and skip_to_dot t = parse
  | newline                   { Lexing.new_line lexbuf; skip_to_dot t lexbuf }
  | comment_begin             { parse_comment lexbuf; skip_to_dot t lexbuf }
  | "." ( newline )           { Lexing.new_line lexbuf }
  | '.' ( whitespace+ | eof)  { () }
  | eof                       { syntax_error lexbuf ~who:"skip_to_dot t"
                                  ~desc:msg_eof ~hint:hint_eof_term }
  | _                         { skip_to_dot t lexbuf }

(* Parser for [Declare ML Module "mod.ule1" "mod.ule2"] *)
and parse_declare t = parse
  | newline       { Lexing.new_line lexbuf; parse_declare t lexbuf }
  | whitespace+   { parse_declare t lexbuf }
  | comment_begin { parse_comment lexbuf; parse_declare t lexbuf }
  | "ML"          { parse_declare_ml t lexbuf }
  | _             { syntax_error lexbuf ~who:"parse_declare"
                      ~desc:(msg_unable lexbuf) }
and parse_declare_ml t = parse
  | newline       { Lexing.new_line lexbuf; parse_declare_ml t lexbuf }
  | whitespace+   { parse_declare_ml t lexbuf }
  | comment_begin { parse_comment lexbuf; parse_declare_ml t lexbuf }
  | "Module"      { parse_ml_modules t [] lexbuf }
  | _             { syntax_error lexbuf ~who:"parse_declare_ml"
                      ~desc:(msg_unable lexbuf) }
and parse_ml_modules t modules = parse
  | newline       { Lexing.new_line lexbuf; parse_ml_modules t modules lexbuf }
  | whitespace+   { parse_ml_modules t modules lexbuf }
  | comment_begin { parse_comment lexbuf; parse_ml_modules t modules lexbuf }
  | coq_qid_quot  { let modules = get_module ~quoted:true lexbuf :: modules in
                    parse_ml_modules t modules lexbuf }
  | '.'           { Token.add_declare_list t modules }
  | eof           { syntax_error lexbuf ~who:"parse_ml_modules"
                      ~desc:msg_eof ~hint:hint_eof_term }
  | _             { syntax_error lexbuf ~who:"parse_ml_modules"
                      ~desc:(msg_unable lexbuf) }

(* The Timeout 1234 command is a noop, but requires parsing an extra token *)
and parse_timeout t = parse
  | newline       { Lexing.new_line lexbuf; parse_timeout t lexbuf }
  | whitespace+   { parse_timeout t lexbuf }
  | comment_begin { parse_comment lexbuf; parse_timeout t lexbuf }
  | ['0'-'9']+    { parse_coq t lexbuf }
  | eof           { syntax_error lexbuf ~who:"parse_timeout" ~desc:msg_eof }
  | _             { syntax_error lexbuf ~who:"parse_timeout"
                      ~desc:(msg_unable lexbuf) }

(** Parser for Require with modifiers *)
and parse_require_modifiers t from = parse
  | newline       { Lexing.new_line lexbuf;
                    parse_require_modifiers t from lexbuf }
  | whitespace    { parse_require_modifiers t from lexbuf }
  | comment_begin { parse_comment lexbuf;
                    parse_require_modifiers t from lexbuf }
  | "Import"      { parse_require_modifiers t from lexbuf }
  | "Export"      { parse_require_modifiers t from lexbuf }
  | "-"           { parse_require_modifiers t from lexbuf }
  | "("           { skip_parenthesized lexbuf;
                    parse_require_modifiers t from lexbuf }
  | eof           { syntax_error lexbuf ~who:"parse_require_modifiers"
                      ~desc:msg_eof }
  | _             { backtrack lexbuf; parse_require t from [] lexbuf }
(** Utility for skipping parenthesized items (used for import categories) *)
and skip_parenthesized = parse
  | newline       { Lexing.new_line lexbuf; skip_parenthesized lexbuf }
  | whitespace    { skip_parenthesized lexbuf }
  | comment_begin { parse_comment lexbuf; skip_parenthesized lexbuf }
  | "("           { skip_parenthesized lexbuf; skip_parenthesized lexbuf }
  | ")"           { () }
  | eof           { raise End_of_file }
  | _             { skip_parenthesized lexbuf }
(* Parser for Require + modules *)
and parse_require t from modules = parse
  | newline       { Lexing.new_line lexbuf;
                    parse_require t from modules lexbuf }
  | whitespace    { parse_require t from modules lexbuf }
  | comment_begin { parse_comment lexbuf;
                    parse_require t from modules lexbuf }
  | "("           { skip_parenthesized lexbuf;
                    parse_require t from modules lexbuf }
  | coq_qualid    { let modules = get_module lexbuf :: modules in
                    parse_require t from modules lexbuf }
  | '.'           { Token.add_from_list t from modules }
  | eof           { syntax_error lexbuf ~who:"parse_require" ~desc:msg_eof
                      ~hint:hint_eof_term }
  | _             { syntax_error lexbuf ~who:"parse_require"
                      ~desc:(msg_unable lexbuf) }

(* From ... Require Import parsing rules *)
and parse_from t = parse
  | newline       { Lexing.new_line lexbuf; parse_from t lexbuf }
  | comment_begin { parse_comment lexbuf; parse_from t lexbuf }
  | whitespace    { parse_from t lexbuf }
  | coq_qualid    { let from = get_module lexbuf in
                    parse_from_require_or_extradep t from lexbuf }
  | eof           { syntax_error lexbuf ~who:"parse_from t" ~desc:msg_eof }
  | _             { syntax_error lexbuf ~who:"parse_from t"
                      ~desc:(msg_unable lexbuf) }
and parse_from_require_or_extradep t from = parse
  | newline       { Lexing.new_line lexbuf;
                    parse_from_require_or_extradep t from lexbuf }
  | comment_begin { parse_comment lexbuf;
                    parse_from_require_or_extradep t from lexbuf }
  | whitespace    { parse_from_require_or_extradep t from lexbuf }
  | "Require"     { parse_require_modifiers t (Some from) lexbuf }
  | "Extra"       { parse_dependency t from lexbuf }
  | eof           { syntax_error lexbuf ~who:"parse_from_require_or_extradep"
                      ~desc:msg_eof }
  | _             { syntax_error lexbuf ~who:"parse_from_require_or_extradep"
                      ~desc:(msg_unable lexbuf) }

(* From ... Extra Dependency ... as ... parsing rules *)
and parse_dependency t from = parse
  | newline       { Lexing.new_line lexbuf; parse_dependency t from lexbuf }
  | comment_begin { parse_comment lexbuf; parse_dependency t from lexbuf }
  | whitespace    { parse_dependency t from lexbuf }
  | "Dependency"  { parse_dependency_file t from lexbuf }
  | eof           { syntax_error lexbuf ~who:"parse_dependency" ~desc:msg_eof }
  | _             { syntax_error lexbuf ~who:"parse_dependency"
                      ~desc:(msg_unable lexbuf) }
and parse_dependency_file t from = parse
  | newline       { Lexing.new_line lexbuf;
                    parse_dependency_file t from lexbuf }
  | comment_begin { parse_comment lexbuf;
                    parse_dependency_file t from lexbuf }
  | whitespace    { parse_dependency_file t from lexbuf }
  | quoted        { let loc = Loc.of_lexbuf lexbuf in
                    let file = get_unquoted_vfile lexbuf in
                    skip_to_dot t lexbuf;
                    Token.add_extrdep t loc from file }
  | eof           { syntax_error lexbuf ~who:"parse_dependency_file"
                      ~desc:msg_eof }
  | _             { syntax_error lexbuf ~who:"parse_dependency_file"
                      ~desc:(msg_unable lexbuf) }

(* Parsing load file *)
and parse_load t = parse
  | newline       { Lexing.new_line lexbuf; parse_load t lexbuf }
  | comment_begin { parse_comment lexbuf; parse_load t lexbuf }
  | whitespace    { parse_load t lexbuf }
  | coq_qualid    { let load = get_module lexbuf in
                    skip_to_dot t lexbuf; Token.add_require t load }
  | quoted        { let loc = Loc.of_lexbuf lexbuf in
                    let path = get_unquoted_vfile lexbuf in
                    skip_to_dot t lexbuf; Token.add_load t loc path }
  | eof           { syntax_error lexbuf ~who:"parse_load" ~desc:msg_eof }
  | _             { syntax_error lexbuf ~who:"parse_load"
                      ~desc:(msg_unable lexbuf) }

(* Vernac Commments parser *)
and parse_vernac_comments t = parse
  | newline       { Lexing.new_line lexbuf; parse_vernac_comments t lexbuf }
  (* This is a backwards compatible way of declaring extra dependencies. *)
  | "From"        { parse_from t lexbuf }
  | '.'           { parse_coq t lexbuf }
  | eof           { syntax_error lexbuf ~who:"parse_vernac_comments"
                      ~desc:msg_eof ~hint:hint_eof_term }
  | _             { parse_vernac_comments t lexbuf }
