open Import

type 'a context

val in_src_file : Path.Source.t -> Path.Source.t context
val in_build_file : Path.Build.t -> Path.Build.t context

(** Like [in_src_file], but routes file reads through [resolver]'s
    backing-aware [file_exists] / [with_lexbuf_from_file] closures. *)
val in_src_file_with_resolver
  :  Source_resolver.t
  -> Path.Source.t
  -> Path.Source.t context

val file_path : 'a context -> Loc.t -> string -> 'a

val load_sexps
  :  context:'a context
  -> Loc.t * string
  -> (Dune_lang.Ast.t list * 'a context) Memo.t
