open Import

val install_file
  :  package:Package.Name.t
  -> findlib_toolchain:Context_name.t option
  -> Filename.t

val symlink_rules : Super_context.t -> dir:Path.Build.t -> (Subdir_set.t * Rules.t) Memo.t

val stanzas_to_entries
  :  Super_context.t
  -> Install.Entry.Sourced.Unexpanded.t list Dune_lang.Package_name.Map.t Memo.t

val resolve_package_install_file
  :  loc:Loc.t
  -> Super_context.t
  -> pkg:Package.Name.t
  -> section:Section.t
  -> file:Path.Local.t
  -> Path.Build.t Memo.t

(** Generate [META.<package-name>] and [.dune-package] rules for the packages
    visible from a loaded project. *)
val gen_project_metadata_rules : Super_context.t -> Loaded_project.t -> unit Memo.t

(** Generate workspace-only package install files, aliases, and odoc configuration. *)
val gen_project_rules : Super_context.t -> Dune_project.t -> unit Memo.t
