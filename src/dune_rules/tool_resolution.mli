open Import

(** Unified tool resolution.

    This module provides a unified interface for resolving and building tools,
    regardless of whether they're configured via (tool) stanza, legacy Dev_tool,
    or should fall back to system PATH.
*)

(** A resolved tool ready for execution.
    Note: exe_path is determined after build by reading the install cookie. *)
type resolved =
  { package : Package.Name.t
  ; version : Package_version.t
  ; install_cookie : Path.Build.t  (** Depend on this to ensure the package is built *)
  ; executable_hint : string option  (** From stanza, if specified *)
  ; env : Env.t Memo.t
  }

val to_dyn : resolved -> Dyn.t

(** Resolution source - how the tool was resolved *)
type resolution_source =
  | From_workspace_stanza of Tool_stanza.t
  | From_legacy_dev_tool of Dune_pkg.Dev_tool.t
  | From_locked_version

val resolution_source_to_dyn : resolution_source -> Dyn.t

(** Resolve a tool by package name.

    Resolution priority:
    1. Check workspace (tool) stanza
    2. Check legacy Dev_tool.t
    3. Check if tool has a lock directory

    Returns None if the tool should be resolved from system PATH. *)
val resolve_opt
  :  package_name:Package.Name.t
  -> (resolved * resolution_source) option Memo.t

(** Resolve a tool, raising an error if not found *)
val resolve : package_name:Package.Name.t -> resolved Memo.t

(** Resolve a tool specifically for formatting (like ocamlformat).
    This also reads the version from .ocamlformat config if present. *)
val resolve_for_formatting
  :  package_name:Package.Name.t
  -> (resolved * resolution_source) option Memo.t

(** Ensure a resolved tool is built and return its executable path.
    This is meant to be used in Action_builder context. *)
val ensure_built : resolved -> Path.t Action_builder.t

(** Get the full action builder for running a resolved tool.
    Includes ensuring the tool is built and adding its environment. *)
val with_tool_env
  :  resolved
  -> f:(exe_path:Path.t -> env:Env.t -> 'a)
  -> 'a Action_builder.t
