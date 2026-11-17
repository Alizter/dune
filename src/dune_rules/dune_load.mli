(** Loads dune files from the workspace and query the workspace for various
    global data such as dune files, projects, pcakages.

    All the functions here are memoized. *)

open Import

(** A memo key for a package in a context. *)
module Context_and_package : Memo.Input with type t = Context_name.t * Package.Name.t

(** The projects and dune files of one partition of a context: the workspace,
    or one mounted package. *)
module Partition : sig
  type t

  val projects_by_output_root : t -> Loaded_project.t Path.Build.Map.t
  val dune_files : t -> Dune_file.t list
end

(** The workspace's projects and dune files in a context. Mounted packages
    are loaded separately, each by its own name. *)
val workspace : Context_name.t -> Partition.t Memo.t

val dune_files : Context_name.t -> Dune_file.t list Memo.t

(** A mounted package's projects and dune files: [None] when the package has
    no mounted source. Loading one fetches its source and raises its errors. *)
val mount : Context_name.t -> Package.Name.t -> Partition.t option Memo.t

(** The errors loading a mounted package raises, for lookups that report them
    without failing. *)
val package_errors : Context_name.t -> Package.Name.t -> User_message.t list Memo.t

(** The dune files that may define a package's stanzas: the workspace's, or
    those of the package's mount. *)
val dune_files_of_package : Context_name.t -> Package.Name.t -> Dune_file.t list Memo.t

(** Static stanzas owned by a package, including deprecated library names,
    in traversal order. A mounted package's stanzas come from its mount. *)
val stanzas_of_package
  :  Context_name.t
  -> Package.Name.t
  -> (Dune_file.t * Stanza.t) list Memo.t

(** The complete input tree enclosing [dir], without loading generated stanzas.
    This root may enclose several projects. *)
val source_tree_root : dir:Path.Build.t -> Source_tree.Rules.Dir.t option Memo.t

val source_tree_dir : dir:Path.Build.t -> Source_tree.Rules.Dir.t option Memo.t
val source_files : dir:Path.Build.t -> Path.Build.Set.t Memo.t
val vendored_warnings : dir:Path.Build.t -> bool Memo.t
val find_loaded_project : dir:Path.Build.t -> Loaded_project.t Memo.t
val find_project : dir:Path.Build.t -> Dune_project.t Memo.t
val stanzas_in_dir : Path.Build.t -> Dune_file.t option Memo.t
val mask : unit -> Only_packages.t Memo.t
val packages : unit -> Package.t Package.Name.Map.t Memo.t

(** A workspace package, or the package of a mounted source. *)
val find_package : Context_name.t -> Package.Name.t -> Package.t option Memo.t

(** Dependency closure, over workspace and locked packages, for package search
    narrowing. *)
val package_closure_for_context
  :  Context_name.t
  -> Package.Name.Set.t
  -> Package.Name.Set.t Memo.t

val projects : unit -> Dune_project.t list Memo.t
