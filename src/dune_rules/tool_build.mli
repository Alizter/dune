open Import

(** Build infrastructure for tools.

    This module provides installation paths and environment handling
    for tools. It uses project-local storage at _build/default/.tools/
*)

(** Base directory name for tools in the build directory *)
val install_path_base_dir_name : string

(** Installation path for a specific tool package version: _build/default/.tools/<package>/<version>/ *)
val install_path : Package.Name.t -> version:Package_version.t -> Path.Build.t

(** Path to the target directory: _build/default/.tools/<package>/<version>/target/ *)
val target_dir : package_name:Package.Name.t -> version:Package_version.t -> Path.Build.t

(** Path to the install cookie: _build/default/.tools/<package>/<version>/target/cookie
    This file is created when the package is fully installed. Depend on this to ensure
    the package is built before accessing files in target/. *)
val install_cookie : package_name:Package.Name.t -> version:Package_version.t -> Path.Build.t

(** Path to a tool's executable: _build/default/.tools/<package>/<version>/target/bin/<exe> *)
val exe_path :
  package_name:Package.Name.t -> version:Package_version.t -> executable:string -> Path.Build.t

(** Get the executable path for a Tool_stanza configuration.
    Requires a version since the stanza may not specify one. *)
val exe_path_of_stanza : Tool_stanza.t -> version:Package_version.t -> Path.Build.t

(** Get the environment for running a tool at a specific version.
    This includes PATH and any other environment variables exported by the tool's package. *)
val tool_env : Package.Name.t -> version:Package_version.t -> Env.t Memo.t

(** Compute bin directories for all configured tools.
    Requires versions to be resolved. *)
val tool_bin_dirs_with_versions : (Tool_stanza.t * Package_version.t) list -> Path.t list

(** Add all tool bin directories to an environment's PATH *)
val add_tools_to_path_with_versions : (Tool_stanza.t * Package_version.t) list -> Env.t -> Env.t

(** Read the list of installed binaries from a tool's install cookie.
    Returns the list of binary names (basenames only).
    Must be called after the package is built (cookie exists). *)
val read_binaries_from_cookie :
  package_name:Package.Name.t -> version:Package_version.t -> string list

(** Select an executable from the available binaries.
    - If explicit executable given, use it
    - If single binary available, use it automatically
    - If multiple binaries, require explicit choice (raises error) *)
val select_executable :
  package_name:Package.Name.t -> version:Package_version.t -> executable_opt:string option -> string
