open Import

(** Lock directory management for tools.

    Tools have separate lock directories from project dependencies:
    - External (source): .tools.lock/<package-name>/
    - Build: _build/default/.tools/<package-name>/
*)

(** External lock directory for a tool package.
    Located at: .tools.lock/<package-name>/ *)
val external_lock_dir : Package.Name.t -> Path.External.t

(** Build lock directory for a tool package.
    Located at: _build/default/.tools/<package-name>/ *)
val build_lock_dir : Package.Name.t -> Path.t

(** Check if a tool has a lock directory *)
val lock_dir_exists : Package.Name.t -> bool Memo.t

(** Load a tool's lock directory *)
val load : Package.Name.t -> Dune_pkg.Lock_dir.t Memo.t

(** Load a tool's lock directory if it exists *)
val load_if_exists : Package.Name.t -> Dune_pkg.Lock_dir.t option Memo.t

(** Convert a legacy Dev_tool.t to the new tool lock directory path.
    Provides backward compatibility during migration. *)
val external_lock_dir_of_dev_tool : Dune_pkg.Dev_tool.t -> Path.External.t

val build_lock_dir_of_dev_tool : Dune_pkg.Dev_tool.t -> Path.t
