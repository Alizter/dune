open Import

val artifact_dir_basename : string

module Candidate : sig
  type t

  val name : t -> Package.Name.t
  val artifact_root : t -> Path.Build.t
  val identity_digest : t -> Dune_digest.t
end

module Mounted : sig
  type kind =
    | Dune
    | Opam of Opam_stanza.t

  type t

  val candidate : t -> Candidate.t
  val source_root : t -> Path.Build.t
  val projects : t -> (Dune_project.t * Source_tree.Rules.Dir.t) list
  val tree : t -> Source_tree.Rules.Build.t
  val kind : t -> kind
  val is_dune : t -> bool
end

val mounted : Context_name.t -> Mounted.t list Memo.t
val find_mounted : Context_name.t -> Package.Name.t -> Mounted.t option Memo.t

val add_artifact_source_rules
  :  dir:Path.Build.t
  -> source_dir:Source_tree.Rules.Dir.t
  -> Build_config.Gen_rules.t
  -> Build_config.Gen_rules.t
