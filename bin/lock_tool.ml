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

(** Get the external lock directory for a tool package.
    Uses the new .tools.lock/<package>/ structure. *)
let tool_external_lock_dir package_name =
  let external_root =
    Path.Build.root |> Path.build |> Path.to_absolute_filename |> Path.External.of_string
  in
  Path.External.relative
    external_root
    (sprintf ".tools.lock/%s" (Package_name.to_string package_name))
;;

let solve ~package_name ~local_packages =
  let open Memo.O in
  let* solver_env_from_current_system =
    Pkg.Pkg_common.poll_solver_env_from_current_system ()
    |> Memo.of_reproducible_fiber
    >>| Option.some
  and* workspace =
    let+ workspace = Workspace.workspace () in
    match Config.get Dune_rules.Compile_time.bin_dev_tools with
    | `Enabled ->
      Workspace.add_repo workspace Dune_pkg.Pkg_workspace.Repository.binary_packages
    | `Disabled -> workspace
  and* compiler_pins = compiler_pins in
  (* as we want to write to the source, we're using the source lock dir here *)
  let lock_dir = tool_external_lock_dir package_name |> Path.external_ in
  Memo.of_reproducible_fiber
  @@ Pkg.Lock.solve
       workspace
       ~local_packages
       ~project_pins:compiler_pins
       ~solver_env_from_current_system
       ~version_preference:None
       ~lock_dirs:[ lock_dir ]
       ~print_perf_stats:false
       ~portable_lock_dir:false
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
let lock_tool_at_version ~package_name ~version ~compiler_compatible =
  let open Memo.O in
  let* extra_deps = extra_dependencies ~compiler_compatible in
  let local_pkg =
    make_local_package_wrapping_tool ~package_name ~version ~extra_dependencies:extra_deps
  in
  let local_packages = Package_name.Map.singleton local_pkg.name local_pkg in
  solve ~package_name ~local_packages
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
  lock_tool_at_version ~package_name ~version ~compiler_compatible
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
    lock_tool_at_version ~package_name ~version:None ~compiler_compatible:false
;;

(** Lock a tool only if lock dir doesn't exist.
    Use for `dune tools run` which should not re-lock existing tools. *)
let lock_tool_if_needed package_name =
  let open Memo.O in
  let tool_lock_dir = tool_external_lock_dir package_name in
  let* lock_dir_exists =
    Dune_engine.Fs_memo.dir_exists (Path.Outside_build_dir.External tool_lock_dir)
  in
  match lock_dir_exists with
  | true -> Memo.return ()
  | false -> lock_tool package_name
;;

(** Lock ocamlformat, reading version from .ocamlformat config if present *)
let lock_ocamlformat () =
  let package_name = Package_name.of_string "ocamlformat" in
  let version = Dune_pkg.Ocamlformat.version_of_current_project's_ocamlformat_config () in
  let open Memo.O in
  let* workspace = Workspace.workspace () in
  let compiler_compatible =
    match Workspace.find_tool workspace package_name with
    | Some stanza -> Tool_stanza.needs_matching_compiler stanza
    | None -> false
  in
  lock_tool_at_version ~package_name ~version ~compiler_compatible
;;
