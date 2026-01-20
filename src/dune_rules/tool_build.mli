open Import

(** Build infrastructure for tools.

    This module provides installation paths and environment handling
    for tools. It uses project-local storage at _build/default/.tools/
*)

(** Base directory name for tools in the build directory *)
val install_path_base_dir_name : string

(** Installation path for a specific tool package: _build/default/.tools/<package>/ *)
val install_path : Package.Name.t -> Path.Build.t

(** Path to a tool's executable: _build/default/.tools/<package>/target/bin/<exe> *)
val exe_path : package_name:Package.Name.t -> executable:string -> Path.Build.t

(** Get the executable path for a Tool_stanza configuration *)
val exe_path_of_stanza : Tool_stanza.t -> Path.Build.t

(** Get the environment for running a tool.
    This includes PATH and any other environment variables exported by the tool's package. *)
val tool_env : Package.Name.t -> Env.t Memo.t

(** Compute bin directories for all configured tools *)
val tool_bin_dirs : Tool_stanza.t list -> Path.t list

(** Add all tool bin directories to an environment's PATH *)
val add_tools_to_path : Tool_stanza.t list -> Env.t -> Env.t
