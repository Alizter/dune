(** Loads dune files from the workspace and query the workspace for various
    global data such as dune files, projects, pcakages.

    All the functions here are memoized. *)

open Import

val dune_files : Context_name.t -> Dune_file.t list Memo.t
val loaded_projects : Context_name.t -> Loaded_project.t list Memo.t
val workspace_projects_by_root : unit -> Dune_project.t Source_path.Map.t Memo.t
val find_loaded_project : dir:Path.Build.t -> Loaded_project.t Memo.t

val find_loaded_project_by_identity
  :  context:Context_name.t
  -> identity:Loaded_project.Identity.t
  -> Loaded_project.t Memo.t

val find_project : dir:Path.Build.t -> Dune_project.t Memo.t
val is_vendored : dir:Path.Build.t -> bool Memo.t
val stanzas_in_dir : Path.Build.t -> Dune_file.t option Memo.t
val mask : unit -> Only_packages.t Memo.t
val packages : unit -> Package.t Package.Name.Map.t Memo.t
val projects : unit -> Dune_project.t list Memo.t
