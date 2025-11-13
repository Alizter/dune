open Import

val setup_rules
  :  components:string list
  -> dir:Path.Build.t
  -> Build_config.Gen_rules.t Memo.t

(** Compute pins by combining project pins with workspace pins, optionally
    filtered by a lock directory's pin list. *)
val workspace_pins
  :  projects:Dune_project.t list
  -> workspace:Workspace.t
  -> lock_dir:Workspace.Lock_dir.t option
  -> Dune_pkg.Pin.DB.t

(** Resolve project pins recursively, traversing pinned sources for additional
    pins. Only dune pins in the sources are considered, opam pins are skipped. *)
val resolve_project_pins
  :  Dune_pkg.Pin.DB.t
  -> Dune_pkg.Resolved_package.t Dune_lang.Package_name.Map.t Fiber.t
