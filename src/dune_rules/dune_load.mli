(** Loads dune files from a context's source tree and exposes per-context views
    of the dune files, projects, and packages enumerated by the walk.

    All the functions here are memoized. *)

open Import

val dune_files : Context_name.t -> Dune_file.t list Memo.t
val projects_by_root : Context_name.t -> Dune_project.t Path.Source.Map.t Memo.t
val find_project : dir:Path.Build.t -> Dune_project.t Memo.t
val stanzas_in_dir : Path.Build.t -> Dune_file.t option Memo.t
val mask : Context_name.t -> Only_packages.t Memo.t
val packages : Context_name.t -> Package.t Package.Name.Map.t Memo.t
val projects : Context_name.t -> Dune_project.t list Memo.t

(** Workspace-aggregate helpers: union the per-context view across all
    registered contexts. Useful when a caller genuinely needs the
    workspace-wide set; prefer the per-context APIs above when a single
    context's view suffices. *)
val workspace_packages : unit -> Package.t Package.Name.Map.t Memo.t

val workspace_projects : unit -> Dune_project.t list Memo.t
