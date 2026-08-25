open Import

val artifact_dir_basename : string

module Candidate : sig
  type t

  val name : t -> Package.Name.t
  val source_root : t -> Path.Build.t
  val artifact_root : t -> Path.Build.t
  val identity_digest : t -> Dune_digest.t
end

module Mounted : sig
  type t

  val candidate : t -> Candidate.t
  val projects : t -> Dune_project.t list

  val dune_files
    :  t
    -> (Source_path.t * Dune_project.t * Source.Dune_file.t) Appendable_list.t
end

val mounted : Context_name.t -> Mounted.t list Memo.t
val find_mounted : Context_name.t -> Package.Name.t -> Mounted.t option Memo.t

val source_rules
  :  context:Context_name.t
  -> dir:Path.Build.t
  -> id:string
  -> Build_config.Gen_rules.t Memo.t

val setup_rules
  :  context:Context_name.t
  -> dir:Path.Build.t
  -> components:string list
  -> Build_config.Gen_rules.t Memo.t

val add_artifact_source_rules
  :  dir:Path.Build.t
  -> source_dir:Path.Build.t
  -> Build_config.Gen_rules.t
  -> Build_config.Gen_rules.t
