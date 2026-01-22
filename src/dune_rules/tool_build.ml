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

(** Installation path for a specific tool package version: _build/default/.tools/<package>/<version>/ *)
let install_path package_name ~version =
  Path.Build.L.relative
    (Lazy.force install_path_base)
    [ Package.Name.to_string package_name; Package_version.to_string version ]
;;

(** Path to the target directory: _build/default/.tools/<package>/<version>/target/ *)
let target_dir ~package_name ~version =
  Path.Build.relative (install_path package_name ~version) "target"
;;

(** Path to the install cookie: _build/default/.tools/<package>/<version>/target/cookie
    This file is created when the package is fully installed. Depend on this to ensure
    the package is built before accessing files in target/. *)
let install_cookie ~package_name ~version =
  Path.Build.relative (target_dir ~package_name ~version) "cookie"
;;

(** Path to a tool's executable: _build/default/.tools/<package>/<version>/target/bin/<exe> *)
let exe_path ~package_name ~version ~executable =
  Path.Build.L.relative (install_path package_name ~version) [ "target"; "bin"; executable ]
;;

(** Get the executable path for a Tool_stanza configuration.
    Requires a version since the stanza may not specify one. *)
let exe_path_of_stanza (tool : Tool_stanza.t) ~version =
  exe_path ~package_name:tool.package ~version ~executable:(Tool_stanza.exe_name tool)
;;

(** Try to convert a package name to a legacy Dev_tool.t *)
let dev_tool_of_package_name_opt package_name =
  try Some (Dune_pkg.Dev_tool.of_package_name package_name) with
  | User_error.E _ -> None
;;

(** Get the environment for running a tool at a specific version.
    This includes PATH and any other environment variables exported by the tool's package. *)
let tool_env package_name ~version =
  Memo.push_stack_frame ~human_readable_description:(fun () ->
    Pp.textf
      "tool environment for %S@%s"
      (Package.Name.to_string package_name)
      (Package_version.to_string version))
  @@ fun () ->
  (* Check if this specific version is locked *)
  let* exists = Tool_lock.version_locked package_name ~version in
  if not exists
  then
    (* No lock dir for this version - use empty env *)
    Memo.return Env.empty
  else
    (* Tool version is locked - get exported env from pkg_rules *)
    let dev_tool_opt = dev_tool_of_package_name_opt package_name in
    match dev_tool_opt with
    | Some dev_tool ->
      (* Use existing pkg_rules infrastructure for legacy tools *)
      Pkg_rules.dev_tool_env dev_tool
    | None ->
      (* For new-style tools, use pkg_rules.tool_env with version *)
      Pkg_rules.tool_env package_name ~version
;;

(** Compute bin directories for all configured tools.
    Requires versions to be resolved. *)
let tool_bin_dirs_with_versions (tools : (Tool_stanza.t * Package_version.t) list) =
  List.map tools ~f:(fun (tool, version) ->
    let bin_dir =
      exe_path
        ~package_name:(Tool_stanza.package_name tool)
        ~version
        ~executable:""
    in
    Path.Build.parent_exn bin_dir |> Path.build)
;;

(** Add all tool bin directories to an environment's PATH *)
let add_tools_to_path_with_versions tools env =
  let bin_dirs = tool_bin_dirs_with_versions tools in
  List.fold_left bin_dirs ~init:env ~f:(fun acc dir -> Env_path.cons acc ~dir)
;;

(** Read the list of installed binaries from a tool's install cookie.
    Returns the list of binary names (basenames only). *)
let read_binaries_from_cookie ~package_name ~version =
  let cookie_path = Path.build (install_cookie ~package_name ~version) in
  let cookie = Pkg_rules.Install_cookie.load_exn cookie_path in
  let files = Pkg_rules.Install_cookie.files cookie in
  match Section.Map.find files Bin with
  | None -> []
  | Some paths -> List.map paths ~f:Path.basename
;;

(** Select an executable from the available binaries.
    - If explicit executable given and exists, use it
    - If single binary available, use it automatically
    - If multiple binaries, require explicit choice *)
let select_executable ~package_name ~version ~executable_opt =
  let binaries = read_binaries_from_cookie ~package_name ~version in
  match executable_opt, binaries with
  | Some exe, _ -> exe  (* Explicit choice *)
  | None, [] ->
    User_error.raise
      [ Pp.textf "Package %S has no binaries installed" (Package.Name.to_string package_name) ]
  | None, [ single ] -> single  (* Auto-select singleton *)
  | None, multiple ->
    User_error.raise
      [ Pp.textf
          "Package %S has multiple binaries: %s"
          (Package.Name.to_string package_name)
          (String.concat ~sep:", " multiple)
      ; Pp.text "Specify which one to use with --bin"
      ]
;;
