(** The opaque rule and dynamic provider interface for [opam] stanzas. *)

open Import

val gen_rules : Context_name.t -> dir:Path.Build.t -> Opam_stanza.t -> unit Memo.t
val package_names : Context_name.t -> Package.Name.Set.t Memo.t
val find_package : Context_name.t -> Package.Name.t -> unit Action_builder.t option Memo.t

val resolve_installed_file
  :  Context_name.t
  -> Package.Name.t
  -> loc:Loc.t
  -> section:Section.t
  -> file:Path.Local.t
  -> Path.t Action_builder.t

val binaries
  :  Context_name.t
  -> packages:Package.Name.Set.t option
  -> Path.t Filename.Map.t Memo.t

val exported_env : Context_name.t -> packages:Package.Name.Set.t option -> Env.t Memo.t
val libraries : Context.t -> Package.Name.t list -> parent:Lib.DB.t -> Lib.DB.t
