open Import

module Identity : sig
  type t

  val workspace : Path.Source.t -> t

  val mounted
    :  lock:Dune_digest.t
    -> package:Package.Name.t
    -> project_root:Path.Local.t
    -> t

  val equal : t -> t -> bool
  val repr : t Repr.t
  val digest : t -> Dune_digest.t
  val to_dyn : t -> Dyn.t
end

module Package_view : sig
  type t

  val workspace : Package_scope.t -> t

  val mounted
    :  package_scope:Package_scope.t
    -> owner_package:Package.t
    -> owner_project:Dune_project.t
    -> t
end

type t

val create
  :  project:Dune_project.t
  -> identity:Identity.t
  -> source_root:Source_path.t
  -> source_tree_root:Source_tree.Rules.Dir.t
  -> partition:Build_partition.t
  -> output_root:Path.Build.t
  -> package_view:Package_view.t
  -> t

val project : t -> Dune_project.t
val identity : t -> Identity.t
val source_root : t -> Source_path.t
val source_tree_root : t -> Source_tree.Rules.Dir.t
val source_tree_dir : t -> Path.Build.t -> Source_tree.Rules.Dir.t option Memo.t
val partition : t -> Build_partition.t
val output_root : t -> Path.Build.t
val visible_packages : t -> Package.Name.Set.t option
val package_scope : t -> Package_scope.t
val package_owner : t -> (Package.t * Dune_project.t) option
val output_path : t -> Source_path.t -> Path.Build.t option
val source_path : t -> Path.Build.t -> Source_path.t option
val to_dyn : t -> Dyn.t
