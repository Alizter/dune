open Import

(** Generic tool locking.

    This module provides functions to lock any opam package as a tool,
    replacing the hardcoded Dev_tool approach with a generic mechanism
    that works with the new (tool) stanza system.
*)

(** Whether auto-locking of dev tools is enabled *)
val is_enabled : bool Lazy.t

(** Lock a tool by package name. Always re-solves.

    First checks the workspace for a (tool) stanza configuration.
    If found, uses the version constraint and compiler_compatible settings.
    If not found, locks with defaults (no version constraint, no compiler matching).

    Writes the lock directory to .tools.lock/<package>/
*)
val lock_tool : Package_name.t -> unit Memo.t

(** Lock a tool only if lock dir doesn't exist.
    Use for `dune tools run` which should not re-lock existing tools. *)
val lock_tool_if_needed : Package_name.t -> unit Memo.t

(** Lock a tool with an explicit version constraint.

    @param package_name The opam package name
    @param version Optional specific version to lock
    @param compiler_compatible If true, add compiler constraints to match project's compiler
*)
val lock_tool_at_version
  :  package_name:Package_name.t
  -> version:Package_version.t option
  -> compiler_compatible:bool
  -> unit Memo.t

(** Lock a tool using configuration from a Tool_stanza.t *)
val lock_tool_from_stanza : Source.Tool_stanza.t -> unit Memo.t

(** Lock ocamlformat, reading version from .ocamlformat config if present *)
val lock_ocamlformat : unit -> unit Memo.t
