open Import
open Memo.O

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

let to_dyn { package; version; install_cookie = _; executable_hint; env = _ } =
  Dyn.record
    [ "package", Package.Name.to_dyn package
    ; "version", Package_version.to_dyn version
    ; "executable_hint", Dyn.option Dyn.string executable_hint
    ]
;;

(** Resolution source - how the tool was resolved *)
type resolution_source =
  | From_workspace_stanza of Tool_stanza.t
  | From_legacy_dev_tool of Dune_pkg.Dev_tool.t
  | From_locked_version

let resolution_source_to_dyn = function
  | From_workspace_stanza stanza ->
    Dyn.variant "From_workspace_stanza" [ Tool_stanza.to_dyn stanza ]
  | From_legacy_dev_tool tool ->
    Dyn.variant "From_legacy_dev_tool" [ Dune_pkg.Dev_tool.to_dyn tool ]
  | From_locked_version -> Dyn.variant "From_locked_version" []
;;

(** Try to find a tool in the workspace's (tool) stanzas *)
let find_in_workspace package_name =
  let+ workspace = Workspace.workspace () in
  Workspace.find_tool workspace package_name
;;

(** Try to convert to a legacy Dev_tool *)
let find_legacy_dev_tool package_name =
  Dune_pkg.Dev_tool.of_package_name_opt package_name
;;

(** Check if a legacy dev tool's lock directory exists.
    This mimics the original dev_tool_lock_dir_exists() check. *)
let legacy_dev_tool_lock_dir_exists dev_tool =
  match Config.get Compile_time.lock_dev_tools with
  | `Enabled -> Memo.return true
  | `Disabled ->
    let path = Lock_dir.dev_tool_external_lock_dir dev_tool in
    Fs_memo.dir_exists (Path.Outside_build_dir.External path)
;;

(** Select a version from available locked versions.
    - 0 versions → None (tool not locked)
    - 1 version → use it
    - N versions → error (user must specify --version) *)
let select_version package_name ~(versions : (Package_version.t * Path.t) list) =
  match versions with
  | [] -> Memo.return None
  | [ (version, _path) ] -> Memo.return (Some version)
  | _ :: _ :: _ as all_versions ->
    let version_strs =
      List.map all_versions ~f:(fun (v, _) -> Package_version.to_string v)
    in
    User_error.raise
      [ Pp.textf
          "Multiple versions of %S are locked: %s"
          (Package.Name.to_string package_name)
          (String.concat ~sep:", " version_strs)
      ; Pp.text "Specify which version to use with --ver or update the (tool) stanza."
      ]
;;

(** Resolve a tool by package name.

    Resolution priority:
    1. Check workspace (tool) stanza with version constraint
    2. Check legacy Dev_tool.t (only if its lock dir exists)
    3. Check if tool has locked versions (new-style .tools.lock/)
    4. Fall back to system PATH (returns None in that case)
*)
let resolve_opt ~package_name =
  let* stanza_opt = find_in_workspace package_name in
  match stanza_opt with
  | Some stanza ->
    (* Found in workspace stanza - determine version *)
    let* versions = Tool_lock.get_locked_versions package_name in
    let* version_opt = select_version package_name ~versions in
    (match version_opt with
     | Some version ->
       let install_cookie = Tool_build.install_cookie ~package_name ~version in
       let executable_hint = Some (Tool_stanza.exe_name stanza) in
       let env = Tool_build.tool_env package_name ~version in
       Memo.return
         (Some ({ package = package_name; version; install_cookie; executable_hint; env }, From_workspace_stanza stanza))
     | None ->
       (* Stanza exists but no locked versions - return None (system PATH) *)
       Memo.return None)
  | None ->
    (* Check for legacy dev tool *)
    (match find_legacy_dev_tool package_name with
     | Some dev_tool ->
       (* Only use legacy dev tool if its lock dir exists *)
       let* lock_exists = legacy_dev_tool_lock_dir_exists dev_tool in
       if lock_exists
       then (
         (* Legacy dev tools: cookie is at <universe_install_path>/target/cookie *)
         let install_cookie =
           Path.Build.L.relative (Pkg_dev_tool.universe_install_path dev_tool) [ "target"; "cookie" ]
         in
         let env = Pkg_rules.dev_tool_env dev_tool in
         (* Legacy dev tools have known exe names *)
         let executable_hint = Some (Dune_pkg.Dev_tool.exe_name dev_tool) in
         (* Legacy dev tools don't have versioned paths, use a placeholder version *)
         let version = Package_version.of_string "legacy" in
         Memo.return
           (Some
              ( { package = package_name; version; install_cookie; executable_hint; env }
              , From_legacy_dev_tool dev_tool )))
       else
         (* Legacy dev tool exists but no lock dir - fall back to system PATH *)
         Memo.return None
     | None ->
       (* Check if there's a lock directory for this package (new-style) *)
       let* versions = Tool_lock.get_locked_versions package_name in
       let* version_opt = select_version package_name ~versions in
       (match version_opt with
        | Some version ->
          (* New-style tool with lock dir but no stanza - discover binary from cookie *)
          let install_cookie = Tool_build.install_cookie ~package_name ~version in
          let env = Tool_build.tool_env package_name ~version in
          Memo.return
            (Some ({ package = package_name; version; install_cookie; executable_hint = None; env }, From_locked_version))
        | None ->
          (* No lock dir - tool should be on system PATH *)
          Memo.return None))
;;

(** Resolve a tool, raising an error if not found *)
let resolve ~package_name =
  let+ result = resolve_opt ~package_name in
  match result with
  | Some (resolved, _source) -> resolved
  | None ->
    User_error.raise
      [ Pp.textf
          "Tool %S is not configured. Add a (tool) stanza to your dune-workspace or \
           install it on your system PATH."
          (Package.Name.to_string package_name)
      ]
;;

(** Resolve a tool specifically for formatting (like ocamlformat).
    This also reads the version from .ocamlformat config if present. *)
let resolve_for_formatting ~package_name =
  resolve_opt ~package_name
;;

(** Ensure a resolved tool is built and return its executable path.
    This is meant to be used in Action_builder context.
    We depend on the install_cookie (not the exe directly) because the package
    produces a directory target. The cookie is created when install completes.
    After build, we read the cookie to discover available binaries. *)
let ensure_built (resolved : resolved) =
  let cookie_path = Path.build resolved.install_cookie in
  let open Action_builder.O in
  let+ () = Action_builder.path cookie_path in
  (* After build, determine the executable from the cookie *)
  let executable =
    Tool_build.select_executable
      ~package_name:resolved.package
      ~version:resolved.version
      ~executable_opt:resolved.executable_hint
  in
  let exe_path =
    Tool_build.exe_path ~package_name:resolved.package ~version:resolved.version ~executable
  in
  Path.build exe_path
;;

(** Get the full action builder for running a resolved tool.
    Includes ensuring the tool is built and adding its environment. *)
let with_tool_env (resolved : resolved) ~f =
  let open Action_builder.O in
  let* exe_path = ensure_built resolved in
  let+ env = Action_builder.of_memo resolved.env in
  f ~exe_path ~env
;;
