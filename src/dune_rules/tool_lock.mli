open Import

(** Lock directory management for tools.

    Tools have separate lock directories from project dependencies:
    - External (source): .tools.lock/<package-name>/<version>/
    - Build: _build/default/.tools/<package-name>/<version>/
*)

(** Check if any version of a tool has a lock directory *)
val any_version_locked : Package.Name.t -> bool Memo.t

(** Get all locked versions of a tool. Returns list of (version, path) pairs. *)
val get_locked_versions : Package.Name.t -> (Package_version.t * Path.t) list Memo.t

(** External lock directory for a specific tool version.
    Located at: .tools.lock/<package-name>/<version>/ *)
val external_lock_dir : Package.Name.t -> version:Package_version.t -> Path.External.t

(** Build lock directory for a specific tool version.
    Located at: _build/default/.tool-locks/<package-name>/<version>/ *)
val build_lock_dir : Package.Name.t -> version:Package_version.t -> Path.t

(** Check if a specific version of a tool has a lock directory *)
val version_locked : Package.Name.t -> version:Package_version.t -> bool Memo.t

(** Load a tool's lock directory for a specific version *)
val load : Package.Name.t -> version:Package_version.t -> Dune_pkg.Lock_dir.t Memo.t

(** Load a tool's lock directory if the version exists *)
val load_if_exists :
  Package.Name.t -> version:Package_version.t -> Dune_pkg.Lock_dir.t option Memo.t

(** Backward compat: Check if any version of a tool is locked.
    Alias for any_version_locked. *)
val lock_dir_exists : Package.Name.t -> bool Memo.t

(** Convert a legacy Dev_tool.t to the new tool lock directory path.
    Provides backward compatibility during migration. *)
val external_lock_dir_of_dev_tool : Dune_pkg.Dev_tool.t -> Path.External.t

val build_lock_dir_of_dev_tool : Dune_pkg.Dev_tool.t -> Path.t
