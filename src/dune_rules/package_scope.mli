open Import

type t

val empty : t
val is_empty : t -> bool

val create
  :  scopes:(Source_path.t * Dune_lang.Scope_stanza.t) list
  -> packages:Package.t list
  -> t

val is_package_visible : t -> Package.t -> bool
val is_stanza_visible : t -> dir:Source_path.t -> Package.Id.t -> bool
val filter_project : t -> Dune_project.t -> Dune_project.t
