open Import
open Memo.O

(** Lock directory management for tools.

    Tools have separate lock directories from project dependencies:
    - External (source): .tools.lock/<package-name>/<version>/
    - Build: _build/default/.tools/<package-name>/<version>/
*)

(** Check if any version of a tool has a lock directory.
    Uses Lock_dir.tool_locked_versions which scans for version subdirectories. *)
let any_version_locked package_name =
  let+ versions = Lock_dir.tool_locked_versions package_name in
  not (List.is_empty versions)
;;

(** Get all locked versions of a tool. Returns list of (version, path) pairs. *)
let get_locked_versions package_name = Lock_dir.tool_locked_versions package_name

(** External lock directory for a specific tool version.
    Located at: .tools.lock/<package-name>/<version>/ *)
let external_lock_dir package_name ~version =
  Lock_dir.tool_external_lock_dir package_name ~version
;;

(** Build lock directory for a specific tool version.
    Located at: _build/default/.tool-locks/<package-name>/<version>/ *)
let build_lock_dir package_name ~version = Lock_dir.tool_lock_dir package_name ~version

(** Check if a specific version of a tool has a lock directory *)
let version_locked package_name ~version =
  Fs_memo.dir_exists
    (Path.Outside_build_dir.External (external_lock_dir package_name ~version))
;;

(** Load a tool's lock directory for a specific version *)
let load package_name ~version = Lock_dir.of_tool package_name ~version

(** Load a tool's lock directory if the version exists *)
let load_if_exists package_name ~version =
  Lock_dir.of_tool_if_lock_dir_exists package_name ~version
;;

(** Backward compat: Check if any version of a tool is locked.
    For tool_resolution to determine if a tool is available. *)
let lock_dir_exists = any_version_locked

(** Convert a legacy Dev_tool.t to the new tool lock directory path.
    Provides backward compatibility during migration. *)
let external_lock_dir_of_dev_tool dev_tool =
  Lock_dir.tool_external_lock_dir_base (Dune_pkg.Dev_tool.package_name dev_tool)
;;

let build_lock_dir_of_dev_tool dev_tool =
  let package_name = Dune_pkg.Dev_tool.package_name dev_tool in
  let ctx_name = Context_name.default |> Context_name.to_string in
  let package_segment = Package.Name.to_string package_name |> Path.Local.of_string in
  let lock_dir =
    Path.Build.L.relative Private_context.t.build_dir [ ctx_name; ".tools" ]
  in
  Path.Build.append_local lock_dir package_segment |> Path.build
;;
