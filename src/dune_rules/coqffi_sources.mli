open Import

val lib : dir:Path.Build.t -> library:Loc.t * Lib_name.t -> Lib.t Memo.t

(** The .v or .ffi targets of the coqffi rule given a module name. *)
val target_of :
  kind:[ `V | `Ffi ] -> dir:Path.Build.t -> Module_name.t -> Path.Build.t

(** Checks if the give list of module names are valid modules that can be found. *)
val modules_of :
     loc:Loc.t
  -> dir:Path.Build.t
  -> library:Loc.t * Lib_name.t
  -> modules:Module_name.t list
  -> ml_sources:Ml_sources.t Memo.t
  -> Module.t list Memo.t

val v_targets : dir:Path.Build.t -> Coqffi_stanza.t -> Path.Build.t list

val modules_of_lib :
     loc:Loc.t
  -> lib:Lib.t
  -> ml_sources:Ml_sources.t Memo.t
  -> (Modules.t * [ `External | `Local ]) Memo.t
