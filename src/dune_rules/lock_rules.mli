open Import

val setup_rules
  :  components:string list
  -> dir:Path.Build.t
  -> Build_config.Gen_rules.t Memo.t

(** Extract pins from a single project, combining both project-level pins and
    package-level pins. *)
val project_and_package_pins : Dune_lang.Dune_project.t -> Dune_pkg.Pin.DB.t

(** Gather pins from all projects and combine them into a single pin database. *)
val all_project_pins : Dune_lang.Dune_project.t list -> Dune_pkg.Pin.DB.t

(** Extract specific pins from workspace pin stanza and combine with project
    pins. This is the common pattern used for combining workspace pins with
    project pins during lock file generation. *)
val combine_with_workspace_pins
  :  workspace_pins:Dune_lang.Pin_stanza.Workspace.t
  -> pin_names:(Loc.t * string) list
  -> Dune_pkg.Pin.DB.t
  -> Dune_pkg.Pin.DB.t

(** Resolve project pins recursively, traversing pinned sources for additional
    pins. This is the standard pattern for resolving pins during lock file
    generation. *)
val resolve_project_pins
  :  Dune_pkg.Pin.DB.t
  -> Dune_pkg.Resolved_package.t Dune_lang.Package_name.Map.t Fiber.t
