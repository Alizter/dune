(** Adapter from the internal stanza to opaque execution. *)

open Import

val gen_rules
  :  Context_name.t
  -> dir:Path.Build.t
  -> string list
  -> Build_config.Gen_rules.result Memo.t

val gen_mounted_rules
  :  Context_name.t
  -> dir:Path.Build.t
  -> string list
  -> Build_config.Gen_rules.result Memo.t
