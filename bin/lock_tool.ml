open Dune_config
open Import
module Lock_dir = Dune_pkg.Lock_dir
module Pin = Dune_pkg.Pin
module Tool_stanza = Source.Tool_stanza

let is_enabled =
  lazy
    (match Config.get Dune_rules.Compile_time.lock_dev_tools with
     | `Enabled -> true
     | `Disabled -> false)
;;

(* Returns a version constraint accepting (almost) all versions whose prefix is
   the given version. This allows alternative distributions of packages to be
   chosen, such as choosing "ocamlformat.0.26.2+binary" when .ocamlformat
   contains "version=0.26.2". *)
let relaxed_version_constraint_of_version version =
  let open Dune_lang in
  let min_version = Package_version.to_string version in
  let max_version = min_version ^ "___MAX_VERSION" in
  Package_constraint.And
    [ Package_constraint.Uop
        (Relop.Gte, Package_constraint.Value.String_literal min_version)
    ; Package_constraint.Uop
        (Relop.Lte, Package_constraint.Value.String_literal max_version)
    ]
;;

(* The solver satisfies dependencies for local packages, but tools
   are not local packages. As a workaround, create an empty local package
   which depends on the tool package. *)
let make_local_package_wrapping_tool ~package_name ~version ~extra_dependencies
  : Dune_pkg.Local_package.t
  =
  let dependency =
    let open Dune_lang in
    let open Package_dependency in
    let constraint_ = Option.map version ~f:relaxed_version_constraint_of_version in
    { name = package_name; constraint_ }
  in
  let local_package_name =
    Package_name.of_string (Package_name.to_string package_name ^ "_tool_wrapper")
  in
  { Dune_pkg.Local_package.name = local_package_name
  ; version = Dune_pkg.Lock_dir.Pkg_info.default_version
  ; dependencies =
      Dune_pkg.Dependency_formula.of_dependencies (dependency :: extra_dependencies)
  ; conflicts = []
  ; depopts = []
  ; pins = Package_name.Map.empty
  ; conflict_class = []
  ; loc = Loc.none
  ; command_source = Opam_file { build = []; install = [] }
  }
;;

(* Collect all pins from all projects and filter to only compiler packages.
   This allows tools to use the same pinned compiler as the main project. *)
let compiler_pins = Memo.O.(Pkg.Lock.project_pins >>| Pin.DB.filter_compilers)

(** Base directory for all tool locks: _build/.tools.lock/ *)
let tools_lock_base () =
  let external_root =
    Path.Build.root |> Path.build |> Path.to_absolute_filename |> Path.External.of_string
  in
  Path.External.relative external_root ".tools.lock"
;;

(** Get the external lock directory for a tool package with version.
    Structure: .tools.lock/<package>/<version>/ *)
let tool_external_lock_dir ~package_name ~version =
  let base = tools_lock_base () in
  let package_segment = Package_name.to_string package_name in
  let version_segment = Package_version.to_string version in
  Path.External.relative base (sprintf "%s/%s" package_segment version_segment)
;;

(** Solve for a tool and write to versioned directory.
    Returns the resolved version.
    If repository_names is provided, only use those repositories. *)
let solve ~package_name ~local_packages ~repository_names =
  let open Memo.O in
  let* solver_env_from_current_system =
    Pkg.Pkg_common.poll_solver_env_from_current_system ()
    |> Memo.of_reproducible_fiber
    >>| Option.some
  and* workspace =
    let+ workspace = Workspace.workspace () in
    let workspace =
      match Config.get Dune_rules.Compile_time.bin_dev_tools with
      | `Enabled ->
        Workspace.add_repo workspace Dune_pkg.Pkg_workspace.Repository.binary_packages
      | `Disabled -> workspace
    in
    (* If repository_names is specified, filter to only those repositories *)
    match repository_names with
    | None -> workspace
    | Some names ->
      let repo_names_set =
        List.map names ~f:Dune_pkg.Pkg_workspace.Repository.Name.of_string
        |> Dune_pkg.Pkg_workspace.Repository.Name.Set.of_list
      in
      Workspace.filter_repositories workspace ~f:(fun repo ->
        Dune_pkg.Pkg_workspace.Repository.Name.Set.mem
          repo_names_set
          (Dune_pkg.Pkg_workspace.Repository.name repo))
  and* compiler_pins = compiler_pins in
  Memo.of_reproducible_fiber
  @@ (let open Fiber.O in
      (* Solve to a temporary location first *)
      let temp_lock_dir =
        Path.External.relative (tools_lock_base ()) ".solving" |> Path.external_
      in
      let* () =
        Pkg.Lock.solve
          workspace
          ~local_packages
          ~project_pins:compiler_pins
          ~solver_env_from_current_system
          ~version_preference:None
          ~lock_dirs:[ temp_lock_dir ]
          ~print_perf_stats:false
          ~portable_lock_dir:false
      in
      (* Read the solved lock dir to get the tool version *)
      let lock_dir_result = Lock_dir.read_disk temp_lock_dir in
      match lock_dir_result with
      | Error msg -> User_error.raise [ User_message.pp msg ]
      | Ok lock_dir ->
        let* platform = Pkg.Pkg_common.poll_solver_env_from_current_system () in
        let packages = Lock_dir.Packages.pkgs_on_platform_by_name lock_dir.packages ~platform in
        (match Package_name.Map.find packages package_name with
         | None ->
           User_error.raise
             [ Pp.textf
                 "Solver did not produce a solution for package %s"
                 (Package_name.to_string package_name)
             ]
         | Some pkg ->
           let version = pkg.info.version in
           let final_lock_dir = tool_external_lock_dir ~package_name ~version in
           let final_path = Path.external_ final_lock_dir in
           (* Convert to Path.Build for rm_rf (path is inside _build/) *)
           let package_segment = Package_name.to_string package_name in
           let version_segment = Package_version.to_string version in
           let final_build_path =
             Path.Build.L.relative Path.Build.root
               [ ".tools.lock"; package_segment; version_segment ]
           in
           Path.mkdir_p (Path.parent_exn final_path);
           Path.rm_rf (Path.build final_build_path);
           Unix.rename (Path.to_string temp_lock_dir) (Path.to_string final_path);
           Fiber.return ()))
;;

(* Detect system OCaml version using Sys_vars from Lock_dir *)
let system_ocaml_version () =
  Memo.Lazy.force Dune_rules.Lock_dir.Sys_vars.poll.sys_ocaml_version
;;

(* Get the compiler package used in the project's lockdir, if available.
   Reads directly from disk to avoid triggering the build system. *)
let compiler_package_opt () =
  let open Memo.O in
  (* Check if dune.lock exists in the workspace *)
  let* workspace = Workspace.workspace () in
  let lock_dir_path = Path.Source.relative workspace.dir "dune.lock" in
  let* exists =
    Dune_engine.Fs_memo.dir_exists (Path.Outside_build_dir.In_source_dir lock_dir_path)
  in
  match exists with
  | false -> Memo.return None
  | true ->
    let lock_dir_full_path = Path.source lock_dir_path in
    (match Lock_dir.read_disk lock_dir_full_path with
     | Error _ -> Memo.return None
     | Ok lockfile ->
       let* platform =
         Pkg.Pkg_common.poll_solver_env_from_current_system () |> Memo.of_reproducible_fiber
       in
       let pkgs = Lock_dir.Packages.pkgs_on_platform_by_name lockfile.packages ~platform in
       (match lockfile.ocaml with
        | None -> Memo.return None
        | Some (_loc, pkg_name) ->
          Memo.return (Package_name.Map.find pkgs pkg_name)))
;;

let compiler_constraints () =
  let open Memo.O in
  let open Dune_lang in
  let* pkg_opt = compiler_package_opt () in
  match pkg_opt with
  | Some pkg ->
    (* Have a project lockdir with compiler - use exact version match *)
    let version = pkg.info.version in
    let constraint_ =
      Some (Package_constraint.Uop (Eq, String_literal (Package_version.to_string version)))
    in
    Memo.return [ { Package_dependency.name = pkg.info.name; constraint_ } ]
  | None ->
    (* No project lockdir - try to detect system OCaml *)
    let+ sys_version = system_ocaml_version () in
    (match sys_version with
     | Some version ->
       (* System OCaml found - require ocaml-system at this version *)
       let constraint_ =
         Some (Package_constraint.Uop (Eq, String_literal version))
       in
       [ { Package_dependency.name = Package_name.of_string "ocaml-system"; constraint_ } ]
     | None ->
       (* No system OCaml found - no compiler constraints *)
       [])
;;

let extra_dependencies ~compiler_compatible:_ =
  (* Tools should use the available OCaml - first check project lock dir,
     then fall back to system OCaml. This ensures tools match the compiler
     version being used. *)
  compiler_constraints ()
;;

(** Lock a tool package with an optional version constraint.
    Always re-solves, like `dune pkg lock`.

    @param package_name The opam package name
    @param version Optional version constraint
    @param compiler_compatible If true, add compiler constraints to match project's compiler
*)
let lock_tool_at_version ~package_name ~version ~compiler_compatible ~repository_names =
  let open Memo.O in
  let* extra_deps = extra_dependencies ~compiler_compatible in
  let local_pkg =
    make_local_package_wrapping_tool ~package_name ~version ~extra_dependencies:extra_deps
  in
  let local_packages = Package_name.Map.singleton local_pkg.name local_pkg in
  solve ~package_name ~local_packages ~repository_names
;;

(** Lock a tool using configuration from a Tool_stanza.t *)
let lock_tool_from_stanza (stanza : Tool_stanza.t) =
  let package_name = Tool_stanza.package_name stanza in
  let version =
    match Tool_stanza.version_constraint stanza with
    | None -> None
    | Some constraint_ ->
      (* Try to extract a specific version from the constraint *)
      (match constraint_ with
       | Dune_lang.Package_constraint.Uop (Eq, String_literal v) ->
         Some (Package_version.of_string v)
       | _ ->
         (* For complex constraints, let the solver handle it *)
         None)
  in
  let compiler_compatible = Tool_stanza.needs_matching_compiler stanza in
  let repository_names = Tool_stanza.repositories stanza in
  lock_tool_at_version ~package_name ~version ~compiler_compatible ~repository_names
;;

(** Lock a tool by package name, checking workspace stanzas first.
    Always re-solves (use for explicit `dune tools lock`). *)
let lock_tool package_name =
  let open Memo.O in
  let* workspace = Workspace.workspace () in
  match Workspace.find_tool workspace package_name with
  | Some stanza -> lock_tool_from_stanza stanza
  | None ->
    (* No stanza - lock with defaults (no version constraint, no compiler matching) *)
    lock_tool_at_version ~package_name ~version:None ~compiler_compatible:false ~repository_names:None
;;

(** Check if any version of a tool is locked.
    Scans .tools.lock/<package>/ for version subdirectories. *)
let any_version_locked package_name =
  let base = tools_lock_base () in
  let package_dir = Path.External.relative base (Package_name.to_string package_name) in
  let package_path = Path.external_ package_dir in
  if not (Path.exists package_path)
  then false
  else (
    match Path.readdir_unsorted package_path with
    | Error _ -> false
    | Ok entries ->
      (* Check if any entry is a directory (version) with lock.dune *)
      List.exists entries ~f:(fun entry ->
        let entry_path = Path.relative package_path entry in
        let lock_dune = Path.relative entry_path "lock.dune" in
        Path.is_directory entry_path && Path.exists lock_dune))
;;

(** Lock a tool only if no version is locked.
    Use for `dune tools run` which should not re-lock existing tools. *)
let lock_tool_if_needed package_name =
  if any_version_locked package_name
  then Memo.return ()
  else lock_tool package_name
;;

(** Lock ocamlformat, reading version from .ocamlformat config if present *)
let lock_ocamlformat () =
  let package_name = Package_name.of_string "ocamlformat" in
  let version = Dune_pkg.Ocamlformat.version_of_current_project's_ocamlformat_config () in
  let open Memo.O in
  let* workspace = Workspace.workspace () in
  let compiler_compatible, repository_names =
    match Workspace.find_tool workspace package_name with
    | Some stanza ->
      Tool_stanza.needs_matching_compiler stanza, Tool_stanza.repositories stanza
    | None -> false, None
  in
  lock_tool_at_version ~package_name ~version ~compiler_compatible ~repository_names
;;
