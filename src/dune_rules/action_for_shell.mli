(** Editable, expanded actions for replay in a prepared shell session. *)

open Import

val encode : Action.t -> dir:Path.t -> Dune_lang.t
val decode : session_root:Path.t -> dir:Path.t -> Action.t Dune_lang.Decoder.t
