open Import

type t =
  | C
  | Cxx
  | Asm

val equal : t -> t -> bool
val to_dyn : t -> Dyn.t
val decode : t Decoder.t

(** The proper name of a language, e.g. "C++" for [Cxx]. Useful for diagnostic
    messages. *)
val proper_name : t -> string

val all : t Nonempty_list.t

module Dict : sig
  type language := t
  type 'a t

  val equal : ('a -> 'a -> bool) -> 'a t -> 'a t -> bool
  val c : 'a t -> 'a
  val cxx : 'a t -> 'a
  val map : 'a t -> f:('a -> 'b) -> 'b t
  val mapi : 'a t -> f:(language:language -> 'a -> 'b) -> 'b t
  val make_all : 'a -> 'a t
  val make : c:'a -> cxx:'a -> 'a t
end

val source_extensions : (t * (int * int)) String.Map.t
val header_extension : Filename.Extension.t
val has_foreign_extension : fn:string -> bool
