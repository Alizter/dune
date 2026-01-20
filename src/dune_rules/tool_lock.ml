open Import

(** Lock directory management for tools.

    Tools have separate lock directories from project dependencies:
    - External (source): .tools.lock/<package-name>/
    - Build: _build/default/.tools/<package-name>/
*)

let package_name_to_path_segment package_name =
  package_name |> Package.Name.to_string |> Path.Local.of_string
;;

(** External lock directory for a tool package.
    Located at: .tools.lock/<package-name>/ *)
let external_lock_dir package_name =
  let external_root =
    Path.Build.root |> Path.build |> Path.to_absolute_filename |> Path.External.of_string
  in
  let tools_lock_path = Path.External.relative external_root ".tools.lock" in
  let package_segment = package_name_to_path_segment package_name in
  Path.External.append_local tools_lock_path package_segment
;;

(** Build lock directory for a tool package.
    Located at: _build/default/.tools/<package-name>/ *)
let build_lock_dir package_name =
  let ctx_name = Context_name.default |> Context_name.to_string in
  let package_segment = package_name_to_path_segment package_name in
  let lock_dir =
    Path.Build.L.relative Private_context.t.build_dir [ ctx_name; ".tools" ]
  in
  Path.Build.append_local lock_dir package_segment |> Path.build
;;

(** Check if a tool has a lock directory.
    Uses Fs_memo to track directory existence. *)
let lock_dir_exists package_name =
  Fs_memo.dir_exists (Path.Outside_build_dir.External (external_lock_dir package_name))
;;

(** Load a tool's lock directory synchronously *)
let load_sync package_name =
  let path = external_lock_dir package_name |> Path.external_ in
  Dune_pkg.Lock_dir.read_disk_exn path
;;

(** Load a tool's lock directory *)
let load package_name = Memo.return (load_sync package_name)

(** Load a tool's lock directory if it exists *)
let load_if_exists package_name =
  let path = external_lock_dir package_name |> Path.external_ in
  let exists = Path.Untracked.exists path in
  if exists then Memo.return (Some (load_sync package_name)) else Memo.return None
;;

(** Convert a legacy Dev_tool.t to the new tool lock directory.
    This provides backward compatibility during migration. *)
let external_lock_dir_of_dev_tool dev_tool =
  external_lock_dir (Dune_pkg.Dev_tool.package_name dev_tool)
;;

let build_lock_dir_of_dev_tool dev_tool =
  build_lock_dir (Dune_pkg.Dev_tool.package_name dev_tool)
;;
