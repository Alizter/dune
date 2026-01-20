open Import
module Tool_build = Dune_rules.Tool_build
module Tool_lock = Dune_rules.Tool_lock
module Tool_stanza = Source.Tool_stanza

(** Get bin directories for all locked tools *)
let get_tool_bin_dirs () =
  let external_root =
    Path.Build.root |> Path.build |> Path.to_absolute_filename |> Path.External.of_string
  in
  let tools_lock_base = Path.External.relative external_root ".tools.lock" in
  let base = Path.external_ tools_lock_base in
  if not (Fpath.exists (Path.to_string base))
  then []
  else (
    match Path.readdir_unsorted base with
    | Error _ -> []
    | Ok pkg_entries ->
      List.concat_map pkg_entries ~f:(fun pkg_name ->
        if String.starts_with pkg_name ~prefix:"."
        then []
        else (
          let pkg_path = Path.relative base pkg_name in
          match Path.readdir_unsorted pkg_path with
          | Error _ -> []
          | Ok version_entries ->
            List.filter_map version_entries ~f:(fun version_str ->
              let version_path = Path.relative pkg_path version_str in
              let cookie = Path.relative version_path "target/cookie" in
              if Fpath.exists (Path.to_string cookie)
              then
                Some
                  (Tool_build.exe_path
                     ~package_name:(Package_name.of_string pkg_name)
                     ~version:(Package_version.of_string version_str)
                     ~executable:""
                   |> Path.Build.parent_exn
                   |> Path.build)
              else None))))
;;

let env_command =
  let term =
    let+ builder = Common.Builder.term
    and+ fish =
      Arg.(
        value
        & flag
        & info
            [ "fish" ]
            ~doc:(Some "Print command for the fish shell rather than POSIX shells"))
    in
    let _ : Common.t * Dune_config.t = Common.init builder in
    let tool_bin_dirs = get_tool_bin_dirs () in
    if fish
    then (
      let space_separated_tool_paths =
        List.map tool_bin_dirs ~f:Path.to_string_maybe_quoted |> String.concat ~sep:" "
      in
      if not (String.is_empty space_separated_tool_paths)
      then print_endline (sprintf "fish_add_path --prepend %s" space_separated_tool_paths))
    else (
      let initial_path = Env.get Env.initial Env_path.var in
      let new_path =
        List.fold_left tool_bin_dirs ~init:initial_path ~f:(fun acc bin_dir ->
          Some (Bin.cons_path bin_dir ~_PATH:acc))
      in
      match new_path with
      | None -> ()
      | Some new_path -> print_endline (sprintf "export %s=%s" Env_path.var new_path))
  in
  let info =
    let doc =
      "Print a command which can be eval'd to enter an environment where all locked \
       tools are runnable as commands."
    in
    Cmd.info "env" ~doc
  in
  Cmd.v info term
;;

(* ========== Generic Tool Support ========== *)

(** Get the install cookie path for a generic tool package at a specific version.
    Depend on this to ensure the package is built. *)
let generic_tool_cookie_path package_name ~version =
  Path.build @@ Tool_build.install_cookie ~package_name ~version
;;

(** Get the exe path for a generic tool package at a specific version.
    Must be called after the package is built (cookie exists).
    If ~bin is provided, use that binary name; otherwise auto-select. *)
let generic_tool_exe_path package_name ~version ~bin =
  let executable =
    Tool_build.select_executable ~package_name ~version ~executable_opt:bin
  in
  Path.build @@ Tool_build.exe_path ~package_name ~version ~executable
;;

(** Build target for a generic tool at a specific version - targets the cookie *)
let generic_tool_build_target package_name ~version =
  Dune_lang.Dep_conf.File
    (Dune_lang.String_with_vars.make_text
       Loc.none
       (Path.to_string (generic_tool_cookie_path package_name ~version)))
;;

(** Parse package spec: "pkg" or "pkg.version" *)
let parse_package_spec spec =
  match String.lsplit2 spec ~on:'.' with
  | None -> Package_name.of_string spec, None
  | Some (pkg, ver) ->
    (* Check if ver looks like a version (starts with digit) or is part of pkg name *)
    if String.length ver > 0 && Char.is_digit ver.[0]
    then Package_name.of_string pkg, Some (Package_version.of_string ver)
    else Package_name.of_string spec, None
;;

(** Select a version from locked versions.
    - If requested_version is Some, use that (error if not locked)
    - 0 versions → error
    - 1 version → use it
    - N versions → error *)
let select_locked_version package_name ~versions ~requested_version =
  match requested_version with
  | Some req_ver ->
    (* User specified a version - check if it's locked *)
    (match List.find versions ~f:(fun (v, _) -> Package_version.equal v req_ver) with
     | Some (v, _) -> v
     | None ->
       User_error.raise
         [ Pp.textf
             "Version %s of %S is not locked."
             (Package_version.to_string req_ver)
             (Package_name.to_string package_name)
         ; Pp.text "Run 'dune tools add' to lock it first."
         ])
  | None ->
    (match versions with
     | [] ->
       User_error.raise
         [ Pp.textf "No versions of %S are locked." (Package_name.to_string package_name)
         ; Pp.text "Run 'dune tools add' first."
         ]
     | [ (version, _path) ] -> version
     | _ :: _ :: _ as all_versions ->
       let version_strs =
         List.map all_versions ~f:(fun (v, _) -> Package_version.to_string v)
       in
       User_error.raise
         [ Pp.textf
             "Multiple versions of %S are locked: %s"
             (Package_name.to_string package_name)
             (String.concat ~sep:", " version_strs)
         ; Pp.text
             "Specify version with package.version syntax (e.g., ocamlformat.0.26.2)."
         ])
;;

let build_generic_tool_directly _common package_name ~requested_version =
  let open Fiber.O in
  let+ result =
    Build.run_build_system ~request:(fun _build_system ->
      let open Action_builder.O in
      (* Only lock if lock dir doesn't exist - don't re-lock on every run *)
      let* () = package_name |> Lock_tool.lock_tool_if_needed |> Action_builder.of_memo in
      (* Get locked versions and select one *)
      let* versions =
        Tool_lock.get_locked_versions package_name |> Action_builder.of_memo
      in
      let version = select_locked_version package_name ~versions ~requested_version in
      (* Depend on the cookie to build the package *)
      Action_builder.path (generic_tool_cookie_path package_name ~version))
  in
  match result with
  | Error `Already_reported -> raise Dune_util.Report_error.Already_reported
  | Ok () -> ()
;;

let build_generic_tool_via_rpc builder lock_held_by package_name ~version =
  let target = generic_tool_build_target package_name ~version in
  let targets = Rpc.Rpc_common.prepare_targets [ target ] in
  let open Fiber.O in
  Rpc.Rpc_common.fire_request
    ~name:"build"
    ~wait:true
    ~lock_held_by
    builder
    Dune_rpc_impl.Decl.build
    targets
  >>| Rpc.Rpc_common.wrap_build_outcome_exn ~print_on_success:false
;;

(** Lock a tool and return the version that was selected.
    Returns the version after locking (either pre-existing or newly created). *)
let lock_and_get_version package_name ~requested_version =
  let open Fiber.O in
  let* () = Lock_tool.lock_tool_if_needed package_name |> Memo.run in
  let+ versions = Tool_lock.get_locked_versions package_name |> Memo.run in
  select_locked_version package_name ~versions ~requested_version
;;

(** Lock and build a generic tool, returning the version that was built. *)
let lock_and_build_generic_tool ~common ~config builder package_name ~requested_version =
  let open Fiber.O in
  match Global_lock.lock ~timeout:None with
  | Error lock_held_by ->
    Scheduler_setup.no_build_no_rpc ~config (fun () ->
      let* version = lock_and_get_version package_name ~requested_version in
      let+ () = build_generic_tool_via_rpc builder lock_held_by package_name ~version in
      version)
  | Ok () ->
    Scheduler_setup.go_with_rpc_server ~common ~config (fun () ->
      let open Fiber.O in
      let* () = build_generic_tool_directly common package_name ~requested_version in
      (* Get the version after building *)
      let+ versions = Tool_lock.get_locked_versions package_name |> Memo.run in
      select_locked_version package_name ~versions ~requested_version)
;;

let run_generic_tool workspace_root package_name ~version ~bin ~args =
  (* Discover the executable from the install cookie *)
  let exe_name =
    Tool_build.select_executable ~package_name ~version ~executable_opt:bin
  in
  let exe_path = Tool_build.exe_path ~package_name ~version ~executable:exe_name in
  let exe_path_string = Path.to_string (Path.build exe_path) in
  Console.finish ();
  (* Add the tool's bin dir to PATH *)
  let bin_dir = Path.Build.parent_exn exe_path |> Path.build in
  let env = Env_path.cons Env.initial ~dir:bin_dir in
  restore_cwd_and_execve workspace_root exe_path_string args env
;;

let lock_build_and_run_generic_tool
      ~common
      ~config
      builder
      package_name
      ~requested_version
      ~bin
      ~args
  =
  let version =
    lock_and_build_generic_tool ~common ~config builder package_name ~requested_version
  in
  run_generic_tool (Common.root common) package_name ~version ~bin ~args
;;

(** Generic exec term for any package (used as default in group) *)
let generic_exec_term =
  let+ builder = Common.Builder.term
  and+ package =
    Arg.(
      required
      & pos
          0
          (some string)
          None
          (info
             []
             ~docv:"PACKAGE[.VERSION]"
             ~doc:(Some "Package to execute (e.g., ocamlformat or ocamlformat.0.26.2)")))
  and+ bin =
    Arg.(
      value
      & opt
          (some string)
          None
          (info
             [ "bin" ]
             ~docv:"BINARY"
             ~doc:(Some "Which binary to run (required if package has multiple binaries)")))
  and+ args = Arg.(value & pos_right 0 string [] (info [] ~docv:"ARGS" ~doc:None)) in
  let common, config = Common.init builder in
  let package_name, requested_version = parse_package_spec package in
  lock_build_and_run_generic_tool
    ~common
    ~config
    builder
    package_name
    ~requested_version
    ~bin
    ~args
;;

(** Generic exec command for any package *)
let generic_exec_command =
  let info =
    let doc =
      "Execute any opam package as a tool. The package will be locked and built if \
       necessary. Pass arguments to the tool after '--'."
    in
    Cmd.info "exec" ~doc
  in
  Cmd.v info generic_exec_term
;;

(** Lock multiple tools *)
let lock_generic_tools ~common ~config specs =
  let open Fiber.O in
  Scheduler_setup.go_with_rpc_server ~common ~config (fun () ->
    Fiber.sequential_iter specs ~f:(fun (package_name, version) ->
      let+ () =
        (let open Memo.O in
         (* Look up stanza to get repositories and compiler_compatible settings *)
         let* workspace = Workspace.workspace () in
         let compiler_compatible, repository_names =
           match Workspace.find_tool workspace package_name with
           | Some stanza ->
             Tool_stanza.needs_matching_compiler stanza, Tool_stanza.repositories stanza
           | None -> false, None
         in
         Lock_tool.lock_tool_at_version
           ~package_name
           ~version
           ~compiler_compatible
           ~repository_names)
        |> Memo.run
      in
      let version_str =
        match version with
        | Some v -> Printf.sprintf "@%s" (Package_version.to_string v)
        | None -> ""
      in
      Console.print_user_message
        (User_message.make
           [ Pp.textf "Locked %s%s" (Package_name.to_string package_name) version_str ])))
;;

(** Generic add term for any package - accepts multiple package.version specs *)
let generic_lock_term =
  let+ builder = Common.Builder.term
  and+ packages =
    Arg.(
      non_empty
      & pos_all
          string
          []
          (info
             []
             ~docv:"PACKAGE[.VERSION]"
             ~doc:(Some "Package specs to lock (e.g., ocamlformat.0.26.2 menhir)")))
  in
  let common, config = Common.init builder in
  let specs = List.map packages ~f:parse_package_spec in
  lock_generic_tools ~common ~config specs
;;

(** Generic add command for any package *)
let generic_lock_command =
  let info =
    let doc =
      "Lock opam packages as tools. Specify versions with package.version syntax."
    in
    Cmd.info "add" ~doc
  in
  Cmd.v info generic_lock_term
;;

(** Synchronously scan for locked versions of a tool.
    Used by "which" command which doesn't have Fiber/Memo context. *)
let scan_locked_versions_sync package_name =
  (* Compute the base path for this tool's versions *)
  let external_root =
    Path.Build.root |> Path.build |> Path.to_absolute_filename |> Path.External.of_string
  in
  let tools_lock_base = Path.External.relative external_root ".tools.lock" in
  let package_dir =
    Path.External.relative tools_lock_base (Package_name.to_string package_name)
  in
  let base = Path.external_ package_dir in
  if not (Fpath.exists (Path.to_string base))
  then []
  else (
    match Path.readdir_unsorted base with
    | Error _ -> []
    | Ok entries ->
      List.filter_map entries ~f:(fun version_str ->
        let version_path = Path.relative base version_str in
        let lock_dune = Path.relative version_path "lock.dune" in
        if Fpath.exists (Path.to_string lock_dune)
        then Some (Package_version.of_string version_str)
        else None))
;;

(** Generic which term for any package (used as default in group) *)
let generic_which_term =
  let+ builder = Common.Builder.term
  and+ package =
    Arg.(
      required
      & pos
          0
          (some string)
          None
          (info
             []
             ~docv:"PACKAGE[.VERSION]"
             ~doc:
               (Some "Package to show path for (e.g., ocamlformat or ocamlformat.0.26.2)")))
  and+ bin =
    Arg.(
      value
      & opt
          (some string)
          None
          (info
             [ "bin" ]
             ~docv:"BINARY"
             ~doc:
               (Some "Which binary to show (required if package has multiple binaries)")))
  and+ allow_not_installed =
    Arg.(
      value
      & flag
      & info
          [ "allow-not-installed" ]
          ~doc:(Some "Print where the tool would be installed even if not installed yet."))
  in
  let _ : Common.t * Dune_config_file.Dune_config.t = Common.init builder in
  let package_name, requested_version = parse_package_spec package in
  let versions = scan_locked_versions_sync package_name in
  (* If user specified a version, filter to just that version *)
  let versions =
    match requested_version with
    | Some req_ver -> List.filter versions ~f:(fun v -> Package_version.equal v req_ver)
    | None -> versions
  in
  match versions with
  | [] ->
    if allow_not_installed
    then (
      (* No version locked - print hypothetical bin directory *)
      let hypothetical_version =
        match requested_version with
        | Some v -> v
        | None -> Package_version.of_string "0.0.0"
      in
      let bin_dir =
        Tool_build.exe_path ~package_name ~version:hypothetical_version ~executable:""
        |> Path.Build.parent_exn
        |> Path.build
      in
      print_endline (Path.to_string bin_dir ^ "/<binary>"))
    else (
      match requested_version with
      | Some v ->
        User_error.raise
          [ Pp.textf
              "Version %s of %S is not locked as a tool"
              (Package_version.to_string v)
              (Package_name.to_string package_name)
          ]
      | None ->
        User_error.raise
          [ Pp.textf "%s is not locked as a tool" (Package_name.to_string package_name) ])
  | [ version ] ->
    let cookie_path = generic_tool_cookie_path package_name ~version in
    if Fpath.exists (Path.to_string cookie_path)
    then (
      (* Package is built - discover binary from cookie *)
      let exe_path = generic_tool_exe_path package_name ~version ~bin in
      print_endline (Path.to_string exe_path))
    else if allow_not_installed
    then (
      (* Package not built yet - show bin directory *)
      let bin_dir =
        Tool_build.exe_path ~package_name ~version ~executable:""
        |> Path.Build.parent_exn
        |> Path.build
      in
      print_endline (Path.to_string bin_dir ^ "/<binary>"))
    else
      User_error.raise
        [ Pp.textf "%s is not installed as a tool" (Package_name.to_string package_name) ]
  | _ :: _ :: _ as all_versions ->
    let version_strs = List.map all_versions ~f:(fun v -> Package_version.to_string v) in
    User_error.raise
      [ Pp.textf
          "Multiple versions of %S are locked: %s"
          (Package_name.to_string package_name)
          (String.concat ~sep:", " version_strs)
      ; Pp.text "Specify version with package.version syntax."
      ]
;;

(** Generic which command for any package *)
let generic_which_command =
  let info =
    let doc =
      "Print the path to a tool's executable. Errors if the tool is not installed."
    in
    Cmd.info "which" ~doc
  in
  Cmd.v info generic_which_term
;;

(** Scan all locked tools and their versions.
    Returns list of (package_name, versions) pairs. *)
let scan_all_locked_tools () =
  let external_root =
    Path.Build.root |> Path.build |> Path.to_absolute_filename |> Path.External.of_string
  in
  let tools_lock_base = Path.External.relative external_root ".tools.lock" in
  let base = Path.external_ tools_lock_base in
  if not (Fpath.exists (Path.to_string base))
  then []
  else (
    match Path.readdir_unsorted base with
    | Error _ -> []
    | Ok pkg_entries ->
      List.filter_map pkg_entries ~f:(fun pkg_name ->
        (* Skip hidden directories like .solving *)
        if String.starts_with pkg_name ~prefix:"."
        then None
        else (
          let pkg_path = Path.relative base pkg_name in
          match Path.readdir_unsorted pkg_path with
          | Error _ -> None
          | Ok version_entries ->
            let versions =
              List.filter_map version_entries ~f:(fun version_str ->
                let version_path = Path.relative pkg_path version_str in
                let lock_dune = Path.relative version_path "lock.dune" in
                if Fpath.exists (Path.to_string lock_dune)
                then Some (Package_version.of_string version_str)
                else None)
            in
            if List.is_empty versions
            then None
            else Some (Package_name.of_string pkg_name, versions))))
;;

(** Generic list term - lists all locked tools *)
let generic_list_term =
  let+ builder = Common.Builder.term in
  let _ : Common.t * Dune_config_file.Dune_config.t = Common.init builder in
  let tools = scan_all_locked_tools () in
  if List.is_empty tools
  then print_endline "No tools are locked."
  else
    List.iter tools ~f:(fun (pkg_name, versions) ->
      let pkg_str = Package_name.to_string pkg_name in
      let version_strs = List.map versions ~f:Package_version.to_string in
      print_endline (sprintf "%s (%s)" pkg_str (String.concat ~sep:", " version_strs)))
;;

(** Generic list command *)
let generic_list_command =
  let info =
    let doc = "List all locked tools and their versions." in
    Cmd.info "list" ~doc
  in
  Cmd.v info generic_list_term
;;

(** Remove a tool's lock directory *)
let remove_tool_lock package_name ~version_opt =
  let external_root =
    Path.Build.root |> Path.build |> Path.to_absolute_filename |> Path.External.of_string
  in
  let tools_lock_base = Path.External.relative external_root ".tools.lock" in
  let pkg_dir =
    Path.External.relative tools_lock_base (Package_name.to_string package_name)
  in
  let pkg_path = Path.external_ pkg_dir in
  if not (Fpath.exists (Path.to_string pkg_path))
  then
    User_error.raise
      [ Pp.textf "Tool %S is not locked." (Package_name.to_string package_name) ]
  else (
    match version_opt with
    | None ->
      (* Remove all versions *)
      let build_path =
        Path.Build.L.relative
          Path.Build.root
          [ ".tools.lock"; Package_name.to_string package_name ]
      in
      Path.rm_rf (Path.build build_path);
      Console.print_user_message
        (User_message.make
           [ Pp.textf "Removed all versions of %s" (Package_name.to_string package_name) ])
    | Some version ->
      (* Remove specific version *)
      let version_str = Package_version.to_string version in
      let version_path = Path.relative pkg_path version_str in
      if not (Fpath.exists (Path.to_string version_path))
      then
        User_error.raise
          [ Pp.textf
              "Version %s of %S is not locked."
              version_str
              (Package_name.to_string package_name)
          ]
      else (
        let build_path =
          Path.Build.L.relative
            Path.Build.root
            [ ".tools.lock"; Package_name.to_string package_name; version_str ]
        in
        Path.rm_rf (Path.build build_path);
        Console.print_user_message
          (User_message.make
             [ Pp.textf "Removed %s@%s" (Package_name.to_string package_name) version_str
             ]);
        (* If no versions left, remove the package directory too *)
        match Path.readdir_unsorted pkg_path with
        | Error _ | Ok [] ->
          let pkg_build_path =
            Path.Build.L.relative
              Path.Build.root
              [ ".tools.lock"; Package_name.to_string package_name ]
          in
          Path.rm_rf (Path.build pkg_build_path)
        | Ok _ -> ()))
;;

(** Generic remove term - removes locked tools *)
let generic_remove_term =
  let+ builder = Common.Builder.term
  and+ packages =
    Arg.(
      non_empty
      & pos_all
          string
          []
          (info
             []
             ~docv:"PACKAGE[.VERSION]"
             ~doc:
               (Some
                  "Package specs to remove (e.g., ocamlformat.0.26.2 or just ocamlformat \
                   for all versions)")))
  in
  let _ : Common.t * Dune_config_file.Dune_config.t = Common.init builder in
  List.iter packages ~f:(fun spec ->
    let package_name, version_opt = parse_package_spec spec in
    remove_tool_lock package_name ~version_opt)
;;

(** Generic remove command *)
let generic_remove_command =
  let info =
    let doc =
      "Remove locked tools. Use package.version to remove specific version, or just \
       package to remove all versions."
    in
    Cmd.info "remove" ~doc
  in
  Cmd.v info generic_remove_term
;;
