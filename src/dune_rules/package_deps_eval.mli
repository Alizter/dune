(** Resolve package names and materialize their immediate action dependencies. *)

open Import

type dependency =
  { loc : Loc.t
  ; name : Package.Name.t
  }

val depend
  :  Context_name.t
  -> dune_version:Dune_lang.Syntax.Version.t
  -> dependency
  -> unit Action_builder.t

val materialize
  :  Context_name.t
  -> dune_version:Dune_lang.Syntax.Version.t
  -> dependency list
  -> Package_deps.t Action_builder.t
