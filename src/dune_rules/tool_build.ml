open Import
open Memo.O

(** Build infrastructure for tools.

    This module provides installation paths and environment handling
    for tools. It uses project-local storage at _build/default/.tools/
*)

(** Base directory name for tools in the build directory *)
let install_path_base_dir_name = ".tools"

(** Base path for all tool installations: _build/default/.tools/ *)
let install_path_base =
  lazy
    (let ctx_name = Context_name.default in
     Path.Build.L.relative
       Private_context.t.build_dir
       [ Context_name.to_string ctx_name; install_path_base_dir_name ])
;;

(** Installation path for a specific tool package: _build/default/.tools/<package>/ *)
let install_path package_name =
  Path.Build.relative (Lazy.force install_path_base) (Package.Name.to_string package_name)
;;

(** Path to a tool's executable: _build/default/.tools/<package>/target/bin/<exe> *)
let exe_path ~package_name ~executable =
  Path.Build.L.relative (install_path package_name) [ "target"; "bin"; executable ]
;;

(** Get the executable path for a Tool_stanza configuration *)
let exe_path_of_stanza (tool : Tool_stanza.t) =
  exe_path ~package_name:tool.package ~executable:(Tool_stanza.exe_name tool)
;;

(** Try to convert a package name to a legacy Dev_tool.t *)
let dev_tool_of_package_name_opt package_name =
  try Some (Dune_pkg.Dev_tool.of_package_name package_name) with
  | User_error.E _ -> None
;;

(** Get the environment for running a tool.
    This includes PATH and any other environment variables exported by the tool's package. *)
let tool_env package_name =
  Memo.push_stack_frame ~human_readable_description:(fun () ->
    Pp.textf "tool environment for %S" (Package.Name.to_string package_name))
  @@ fun () ->
  (* Check if tool has a lock directory *)
  let* exists = Tool_lock.lock_dir_exists package_name in
  if not exists
  then
    (* No lock dir - tool should be on system PATH, use empty env *)
    Memo.return Env.empty
  else
    (* Tool is locked - get exported env from pkg_rules *)
    let dev_tool_opt = dev_tool_of_package_name_opt package_name in
    match dev_tool_opt with
    | Some dev_tool ->
      (* Use existing pkg_rules infrastructure for legacy tools *)
      Pkg_rules.dev_tool_env dev_tool
    | None ->
      (* For new-style tools, we need to build up the environment manually.
         For now, just add the tool's bin directory to PATH. *)
      let bin_dir = Path.build (exe_path ~package_name ~executable:"") |> Path.parent_exn in
      Memo.return (Env_path.cons Env.empty ~dir:bin_dir)
;;

(** Compute bin directories for all configured tools *)
let tool_bin_dirs (tools : Tool_stanza.t list) =
  List.map tools ~f:(fun tool ->
    let bin_dir = exe_path ~package_name:(Tool_stanza.package_name tool) ~executable:"" in
    Path.Build.parent_exn bin_dir |> Path.build)
;;

(** Add all tool bin directories to an environment's PATH *)
let add_tools_to_path tools env =
  let bin_dirs = tool_bin_dirs tools in
  List.fold_left bin_dirs ~init:env ~f:(fun acc dir -> Env_path.cons acc ~dir)
;;
