open Import

type target_type =
  | File
  | Directory

(** List of all buildable direct targets. This does not include files and
    directories produced under a directory target.

    If the directory argument is [None], load the root, otherwise only load
    targets from the nearest subdirectory. [include_source_files] controls
    whether file targets that also exist in the source tree are returned. *)
val all_direct_targets
  :  Path.Source.t option
  -> include_source_files:bool
  -> target_type Path.Build.Map.t Memo.t

val interpret_targets
  :  Workspace_root.t
  -> Dune_rules.Main.build_system
  -> Arg.Dep.t list
  -> unit Dune_engine.Action_builder.t

val expand_path_from_root
  :  Workspace_root.t
  -> Dune_rules.Super_context.t
  -> Dune_lang.String_with_vars.t
  -> string Dune_engine.Action_builder.t
