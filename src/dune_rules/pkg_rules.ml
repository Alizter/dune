open Import
open Memo.O

include struct
  open Dune_pkg
  module Package_variable = Package_variable
  module Substs = Substs
  module Checksum = Checksum
  module Source = Source
  module Build_command = Lock_dir.Build_command
  module Pkg_info = Lock_dir.Pkg_info
  module Depexts = Lock_dir.Depexts
  module Digest_feed = Dune_digest.Feed
  module Dune_dep = Dune_dep
end

module Variable = Opam_package_rules.Variable
module Package_universe = Opam_package_rules.Package_universe
module Pkg_digest = Opam_package_rules.Pkg_digest
module Paths = Opam_package_rules.Paths
module Install_cookie = Opam_package_rules.Install_cookie
module Value_list_env = Opam_package_rules.Value_list_env
module Env_update = Opam_package_rules.Env_update
module Pkg = Opam_package_rules.Pkg
module Pkg_installed = Opam_package_rules.Pkg_installed
module Dependency_view = Opam_package_rules.Dependency_view
module Action_expander = Opam_package_rules.Action_expander

module DB = struct
  let default_system_provided = Package.Name.Set.singleton Dune_pkg.Dune_dep.name

  module Pkg_table = struct
    module Pkg = Lock_dir.Pkg

    type dep =
      { dep_pkg : Pkg.t
      ; dep_loc : Loc.t
      ; dep_pkg_digest : Pkg_digest.t
      }

    type entry =
      { pkg : Pkg.t
      ; deps : dep list
      ; has_dune_dep : bool
      ; pkg_digest : Pkg_digest.t
      }

    let entries_by_name_of_lock_dir
          (lock_dir : Dune_pkg.Lock_dir.t)
          ~platform
          ~system_provided
      =
      let start = Time.now () in
      let pkgs_by_name = Dune_pkg.Lock_dir.packages_on_platform lock_dir ~platform in
      let cache =
        (* Cache so that the digest of each package is only computed once *)
        Package.Name.Table.create 10
      in
      let rec compute_entry (pkg : Pkg.t) ~seen_set ~seen_list =
        if Package.Name.Set.mem seen_set pkg.info.name
        then
          User_error.raise
            [ Pp.textf "Dependency cycle between packages:"
            ; Pp.chain
                (List.rev (pkg :: seen_list))
                ~f:(fun (pkg : Pkg.t) ->
                  Pp.textf
                    "%s.%s"
                    (Package.Name.to_string pkg.info.name)
                    (Package_version.to_string pkg.info.version))
            ];
        Package.Name.Table.find_or_add cache pkg.info.name ~f:(fun name ->
          let seen_set = Package.Name.Set.add seen_set name in
          let seen_list = pkg :: seen_list in
          let has_dune_dep, deps =
            Dune_pkg.Lock_dir.Conditional_choice.choose_for_platform pkg.depends ~platform
            |> Option.value ~default:[]
            |> List.fold_right
                 ~init:(false, [])
                 ~f:
                   (fun
                     { Dune_pkg.Lock_dir.Dependency.name; loc = dep_loc }
                     (has_dune_dep, acc)
                   ->
                   match
                     ( Dune_lang.Package_name.equal name Dune_dep.name
                     , Package.Name.Set.mem system_provided name )
                   with
                   | true, _ -> true, acc
                   | false, true -> has_dune_dep, acc
                   | _, false ->
                     let dep_pkg = Package.Name.Map.find_exn pkgs_by_name name in
                     let dep_entry = compute_entry dep_pkg ~seen_set ~seen_list in
                     ( has_dune_dep
                     , { dep_pkg; dep_loc; dep_pkg_digest = dep_entry.pkg_digest } :: acc
                     ))
          in
          let pkg_digest =
            Pkg_digest.create
              pkg
              (List.map deps ~f:(fun { dep_pkg_digest; _ } -> dep_pkg_digest))
          in
          { pkg; deps; has_dune_dep; pkg_digest })
      in
      let entries =
        Package.Name.Map.map
          pkgs_by_name
          ~f:(compute_entry ~seen_set:Package.Name.Set.empty ~seen_list:[])
      in
      Dune_trace.emit Pkg (fun () ->
        Dune_trace.Event.package_digest_table
          ~start
          ~stop:(Time.now ())
          ~packages:(Package.Name.Map.cardinal entries));
      entries
    ;;

    (* Associate each package's digest with the package and its dependencies. *)
    type t = entry Pkg_digest.Map.t

    type index =
      { entries_by_name : entry Package.Name.Map.t
      ; entries_by_digest : t
      }

    let index_of_lock_dir lock_dir ~platform ~system_provided =
      let entries_by_name =
        entries_by_name_of_lock_dir lock_dir ~platform ~system_provided
      in
      let entries_by_digest =
        Package.Name.Map.values entries_by_name
        |> Pkg_digest.Map.of_list_map_exn ~f:(fun entry -> entry.pkg_digest, entry)
      in
      { entries_by_name; entries_by_digest }
    ;;

    let find_digest_by_name { entries_by_name; _ } name =
      Package.Name.Map.find entries_by_name name
      |> Option.map ~f:(fun { pkg_digest; _ } -> pkg_digest)
    ;;

    let digest_by_name index name = find_digest_by_name index name |> Option.value_exn
  end

  module Id = Id.Make ()

  type t =
    { id : Id.t
    ; pkg_digest_table : Pkg_table.t
    }

  let equal x y = Id.equal x.id y.id
  let create ~pkg_digest_table = { id = Id.gen (); pkg_digest_table }

  module Lock_dir_index_key = struct
    type t =
      { path : Path.t
      ; lock_dir : Dune_pkg.Lock_dir.t
      ; platform : Dune_pkg.Solver_env.t
      }

    let to_dyn { path; lock_dir = _; platform } =
      Dyn.record
        [ "path", Path.to_dyn path; "platform", Dune_pkg.Solver_env.to_dyn platform ]
    ;;

    (* The index retains locations and hashes ordered package data, so the lock
       directory part of this key must use structural equality. *)
    let hash { path; lock_dir; platform } =
      Tuple.T3.hash Path.hash Poly.hash Dune_pkg.Solver_env.hash (path, lock_dir, platform)
    ;;

    let equal { path; lock_dir; platform } t =
      Path.equal path t.path
      && Poly.equal lock_dir t.lock_dir
      && Dune_pkg.Solver_env.equal platform t.platform
    ;;
  end

  let lock_dir_index =
    let memo =
      Memo.create "pkg-db-lock-dir-index" ~input:(module Lock_dir_index_key)
      @@ fun { path = _; lock_dir; platform } ->
      Pkg_table.index_of_lock_dir
        lock_dir
        ~platform
        ~system_provided:default_system_provided
      |> Memo.return
    in
    fun path lock_dir platform -> Memo.exec memo { path; lock_dir; platform }
  ;;

  let of_dev_tool =
    let memo =
      Memo.create "pkg-db-dev-tool" ~input:(module Dune_pkg.Dev_tool)
      @@ fun dev_tool ->
      let* lock_dir = Lock_dir.of_dev_tool dev_tool
      and* platform = Lock_dir.Sys_vars.solver_env in
      let path = Lock_dir.dev_tool_external_lock_dir dev_tool |> Path.external_ in
      let+ index = lock_dir_index path lock_dir platform in
      ( create ~pkg_digest_table:index.Pkg_table.entries_by_digest
      , Pkg_table.digest_by_name index (Pkg_dev_tool.package_name dev_tool) )
    in
    fun dev_tool -> Memo.exec memo dev_tool
  ;;
end

let opam_paths mounted package_name =
  let candidate = Pkg_sources.Mounted.candidate mounted in
  let root =
    Path.Build.L.relative
      (Pkg_sources.Candidate.artifact_root candidate)
      [ ".opam"; Package.Name.to_string package_name ]
  in
  let write_paths =
    Opam_package_rules.Paths.of_root package_name ~root ~relative:Path.Build.relative
  in
  let write_paths =
    { write_paths with source_dir = Pkg_sources.Mounted.working_dir mounted }
  in
  let paths = Opam_package_rules.Paths.map_path write_paths ~f:Path.build in
  paths, write_paths
;;

module Mounted_packages = struct
  let create context =
    let+ mounted = Pkg_sources.mounted context in
    Package.Name.Map.of_list_map_exn mounted ~f:(fun mounted ->
      let candidate = Pkg_sources.Mounted.candidate mounted in
      Pkg_sources.Candidate.name candidate, mounted)
  ;;

  let package = Pkg_sources.Mounted.package

  let local_package mounted =
    match Pkg_sources.Mounted.kind mounted with
    | Opam stanza -> stanza.package
    | Dune ->
      let name = Pkg_sources.Mounted.candidate mounted |> Pkg_sources.Candidate.name in
      Pkg_sources.Mounted.projects mounted
      |> List.find_map ~f:(fun (project, _) ->
        Package.Name.Map.find (Dune_project.including_hidden_packages project) name)
      |> Option.value_exn
  ;;

  let provider mounted =
    match Pkg_sources.Mounted.kind mounted with
    | Dune -> Opam_package_rules.Dependency_provider.Local (local_package mounted)
    | Opam stanza ->
      let name = Package.name stanza.package in
      let _, paths = opam_paths mounted name in
      Opam_package_rules.Dependency_provider.Opam { stanza; paths }
  ;;

  let forwards_capabilities mounted =
    let name = Pkg_sources.Mounted.candidate mounted |> Pkg_sources.Candidate.name in
    if Dune_pkg.Dev_tool.is_compiler_package name
    then true
    else (
      match Pkg_sources.Mounted.source_kind mounted, Pkg_sources.Mounted.kind mounted with
      | No_source, Opam { build = None; install = None; _ } -> true
      | (Primary_source | No_source), (Dune | Opam _) -> false)
  ;;

  let dependencies mounted =
    Package.depends (package mounted)
    |> List.filter_map ~f:(fun dependency ->
      let name = dependency.Package_dependency.name in
      Option.some_if (not (Package.Name.equal name Dune_pkg.Dune_dep.name)) name)
  ;;

  let find t name = Package.Name.Map.find t name

  let find_exn t name =
    match find t name with
    | Some mounted -> mounted
    | None ->
      Code_error.raise
        "Lock package dependency is missing from the mounted package index"
        [ "package", Package.Name.to_dyn name ]
  ;;

  let selected t packages =
    match packages with
    | None -> Package.Name.Map.values t
    | Some packages -> Package.Name.Set.to_list packages |> List.filter_map ~f:(find t)
  ;;

  let closure_if t roots ~follow =
    let rec visit name (visited, ordered) =
      if Package.Name.Set.mem visited name
      then visited, ordered
      else (
        match find t name with
        | None -> visited, ordered
        | Some mounted ->
          let visited = Package.Name.Set.add visited name in
          let visited, ordered =
            if follow mounted
            then
              List.fold_left
                (dependencies mounted)
                ~init:(visited, ordered)
                ~f:(fun acc name -> visit name acc)
            else visited, ordered
          in
          visited, mounted :: ordered)
    in
    List.fold_left roots ~init:(Package.Name.Set.empty, []) ~f:(fun acc name ->
      visit name acc)
    |> snd
    |> List.rev
  ;;

  let closure t roots = closure_if t roots ~follow:(Fun.const true)
  let capability_closure t roots = closure_if t roots ~follow:forwards_capabilities

  let materialize_capabilities context packages direct =
    let open Action_builder.O in
    let direct_names =
      List.map direct ~f:(fun mounted -> Package.name (package mounted))
    in
    let direct_name_set = Package.Name.Set.of_list direct_names in
    let all = capability_closure packages direct_names in
    let+ all =
      List.map all ~f:provider
      |> Opam_package_rules.Dependency_provider.materialize context
    in
    let packages =
      Package.Name.Map.filteri all.packages ~f:(fun name _ ->
        Package.Name.Set.mem direct_name_set name)
    in
    { all with packages }
  ;;

  let binaries context mounted =
    let native_names =
      List.filter_map mounted ~f:(fun mounted ->
        match Pkg_sources.Mounted.kind mounted with
        | Dune -> Some (Package.name (package mounted))
        | Opam _ -> None)
      |> Package.Name.Set.of_list
    in
    let* native =
      if Package.Name.Set.is_empty native_names
      then Memo.return Filename.Map.empty
      else Install_layout.binaries context native_names
    in
    Memo.List.fold_left mounted ~init:native ~f:(fun binaries mounted ->
      match Pkg_sources.Mounted.kind mounted with
      | Dune -> Memo.return binaries
      | Opam stanza ->
        let paths, _ = opam_paths mounted (Package.name stanza.package) in
        let* () = Build_system.build_file (Paths.install_cookie paths) in
        let cookie = Paths.install_cookie paths |> Install_cookie.load_exn in
        Section.Map.Multi.find cookie.files Bin
        |> List.fold_left ~init:binaries ~f:(fun binaries path ->
          let name =
            Path.basename path
            |> Filename.to_string
            |> Bin.strip_exe
            |> Filename.of_string_exn
          in
          Filename.Map.set binaries name path)
        |> Memo.return)
  ;;

  let environment context mounted =
    let native_names =
      List.filter_map mounted ~f:(fun mounted ->
        match Pkg_sources.Mounted.kind mounted with
        | Dune -> Some (Package.name (package mounted))
        | Opam _ -> None)
      |> Package.Name.Set.of_list
    in
    let install_root = Install_layout.root context native_names |> Path.build in
    Memo.List.fold_left mounted ~init:Package_deps.empty ~f:(fun acc mounted ->
      let package = package mounted in
      let stanza, paths =
        match Pkg_sources.Mounted.kind mounted with
        | Opam stanza ->
          let paths, _ = opam_paths mounted (Package.name package) in
          stanza, paths
        | Dune ->
          let lock_pkg =
            Pkg_sources.Mounted.candidate mounted |> Pkg_sources.Candidate.lock_pkg
          in
          ( { Opam_stanza.loc = Loc.none
            ; origin = Lock
            ; package
            ; build = None
            ; install = None
            ; depexts = lock_pkg.depexts
            ; exported_env = lock_pkg.exported_env
            }
          , Package_deps.Paths.of_local_package package ~install_root )
      in
      let variables = Package_deps.variables package in
      let+ exported_env =
        Opam_package_rules.Action_expander.exported_env_of_stanza
          context
          stanza
          ~paths
          ~variables
          acc
      in
      Package_deps.add_package
        acc
        ~paths
        ~variables
        ~files:Section.Map.empty
        ~exported_env)
  ;;
end

let dependency_view_for_package context (pkg : Pkg.t) =
  Dependency_view.of_list context (Pkg.deps_closure pkg) ~is_mounted:(fun _ ->
    Memo.return false)
;;

module rec Resolve : sig
  val resolve : DB.t -> Loc.t -> Pkg_digest.t -> Package_universe.t -> Pkg.t Memo.t
end = struct
  open Resolve

  module Input = struct
    type t =
      { db : DB.t
      ; pkg_digest : Pkg_digest.t
      ; universe : Package_universe.t
      }

    let equal { db; pkg_digest; universe } t =
      Pkg_digest.equal pkg_digest t.pkg_digest
      && Package_universe.equal universe t.universe
      && DB.equal db t.db
    ;;

    let hash { db = _; pkg_digest; universe } =
      Tuple.T2.hash Pkg_digest.hash Package_universe.hash (pkg_digest, universe)
    ;;

    let to_dyn = Dyn.opaque
  end

  let relocate action =
    let string_with_vars =
      String_with_vars.map_loc ~f:Dune_pkg.Lock_dir.loc_in_source_tree
    in
    let slang = Slang.map_loc ~f:Dune_pkg.Lock_dir.loc_in_source_tree in
    let blang = Slang.Blang.map_loc ~f:Dune_pkg.Lock_dir.loc_in_source_tree in
    Dune_lang.Action.map action ~string_with_vars ~slang ~blang
  ;;

  let relocate_build b =
    match (b : Build_command.t) with
    | Dune -> Build_command.Dune
    | Action a -> Build_command.Action (relocate a)
  ;;

  let is_relocatable_compiler_marker name =
    let relocatable_compiler = Package.Name.of_string "relocatable-compiler" in
    let relocatable = Package.Name.of_string "relocatable" in
    Package.Name.equal name relocatable_compiler || Package.Name.equal name relocatable
  ;;

  let has_relocatable_compiler_marker (info : Pkg_info.t) depends =
    is_relocatable_compiler_marker info.name
    || Pkg.top_closure depends
       |> List.exists ~f:(fun (pkg : Pkg.t) ->
         is_relocatable_compiler_marker pkg.info.name)
  ;;

  let is_compiler_version_relocatable (info : Pkg_info.t) =
    Pkg_toolchain.is_compiler_package_with_toolchains_enabled info.name
    &&
    match Package_version.compare info.version (Package_version.of_string "5.5.0") with
    | Lt -> false
    | Eq | Gt -> true
  ;;

  let resolve_impl { Input.db; pkg_digest; universe = package_universe } =
    match Pkg_digest.Map.find db.pkg_digest_table pkg_digest with
    | None -> Memo.return None
    | Some
        { pkg =
            { Lock_dir.Pkg.build_command
            ; install_command
            ; depends = _
            ; info
            ; exported_env
            ; depexts
            ; enabled_on_platforms = _
            } as pkg
        ; deps
        ; has_dune_dep
        ; pkg_digest = _
        } ->
      assert (Package.Name.equal pkg_digest.name info.name);
      let* platform = Lock_dir.Sys_vars.solver_env in
      let choose_for_current_platform field =
        Dune_pkg.Lock_dir.Conditional_choice.choose_for_platform field ~platform
      in
      let* depends =
        Memo.parallel_map
          deps
          ~f:(fun { DB.Pkg_table.dep_pkg = _; dep_loc; dep_pkg_digest } ->
            let package_universe =
              match package_universe with
              | Dev_tool dev_tool -> Package_universe.Dev_tool_dependency dev_tool
              | Dev_tool_dependency _ -> package_universe
            in
            resolve db dep_loc dep_pkg_digest package_universe)
      and+ files_dir =
        let+ lock_dir_path =
          Package_universe.lock_dir_path package_universe >>| Option.value_exn
        and+ lock_dir = Package_universe.lock_dir package_universe in
        let version =
          Option.some_if (Dune_pkg.Lock_dir.uses_versioned_paths lock_dir) info.version
        in
        Dune_pkg.Lock_dir.Pkg.files_dir info.name version ~lock_dir:lock_dir_path
        |> Path.as_in_build_dir_exn
      in
      let id = Pkg.Id.gen () in
      let write_paths =
        Paths.make pkg_digest package_universe ~relative:Path.Build.relative
      in
      let install_command = choose_for_current_platform install_command in
      let install_command = Option.map install_command ~f:relocate in
      let build_command = choose_for_current_platform build_command in
      let build_command = Option.map build_command ~f:relocate_build in
      let paths =
        let paths = Paths.map_path write_paths ~f:Path.build in
        if
          (not (Pkg_toolchain.is_compiler_package_with_toolchains_enabled info.name))
          || is_compiler_version_relocatable info
          || has_relocatable_compiler_marker info depends
        then paths
        else (
          (* Modify the environment as well as build and install commands for
             the compiler package. The specific changes are:
             - setting the prefix in the build environment to inside the user's
               toolchain directory
             - changing the install command so that the
               package is installed with the DESTDIR variable set to a
               temporary directory, and the result is then moved to the user's
               toolchain directory
             - if a matching version of the compiler is
               already installed in the user's toolchain directory then the
               build and install commands are replaced with no-ops
             *)
          let prefix = Pkg_toolchain.installation_prefix pkg in
          let install_roots =
            Pkg_toolchain.install_roots ~prefix
            |> Install.Roots.map ~f:Path.outside_build_dir
          in
          { paths with
            prefix = Path.outside_build_dir prefix
          ; install_roots = Lazy.from_val install_roots
          })
      in
      let t =
        { Pkg.id
        ; build_command
        ; install_command
        ; depends
        ; depends_on_dune = has_dune_dep
        ; depexts
        ; paths
        ; write_paths
        ; info
        ; files_dir
        ; pkg_digest
        ; unexpanded_exported_env = exported_env
        ; exported_env = []
        }
      in
      let* dependencies =
        dependency_view_for_package (Package_universe.context_name package_universe) t
      in
      let* () =
        Action_expander.refresh_exported_env
          (Package_universe.context_name package_universe)
          dependencies
      in
      let+ exported_env =
        let expander =
          Action_expander.expander
            (Package_universe.context_name package_universe)
            t
            dependencies
        in
        Memo.parallel_map exported_env ~f:(Action_expander.exported_env expander)
      in
      t.exported_env <- exported_env;
      Some t
  ;;

  let resolve =
    let memo =
      Memo.create
        "pkg-resolve"
        ~input:(module Input)
        ~human_readable_description:(fun t ->
          Pp.textf "- package %s" (Package.Name.to_string t.pkg_digest.name)
          |> Option.some)
        resolve_impl
    in
    fun (db : DB.t) loc pkg_digest package_universe ->
      Memo.exec memo { db; pkg_digest; universe = package_universe }
      >>| function
      | Some s -> s
      | None ->
        User_error.raise
          ~loc
          [ Pp.textf "Unknown package %S" (Package.Name.to_string pkg_digest.name) ]
  ;;
end

let gen_dev_tool_rules context_name (pkg : Pkg.t) =
  let* dependencies =
    Dependency_view.make context_name pkg ~is_mounted:(fun _ -> Memo.return false)
  in
  let* source_deps, copy_rules = Opam_package_rules.source_rules pkg in
  let* () = copy_rules in
  let source =
    { Opam_package_rules.Source_input.root = pkg.write_paths.source_dir
    ; kind =
        (match pkg.info.source with
         | Some _ -> Directory
         | None -> No_source)
    ; files_dir = Some pkg.files_dir
    ; extra_sources =
        List.map pkg.info.extra_sources ~f:(fun (local, _) ->
          local, Paths.extra_source pkg.paths local)
    }
  in
  Opam_package_rules.gen_dev_tool_rules
    context_name
    pkg
    ~source
    ~source_deps
    ~dependencies
;;

module Gen_rules = Build_config.Gen_rules

let pkg_alias_disabled =
  Action_builder.fail
    { fail =
        (fun () ->
          let error =
            [ Pp.text "The @pkg-install alias cannot be used without a lock dir" ]
          in
          let hints =
            [ Pp.concat
                ~sep:Pp.space
                [ Pp.text "You might want to create the lock dir with"
                ; User_message.command "dune pkg lock"
                ]
            ]
          in
          User_error.raise ~hints error)
    }
;;

let setup_pkg_install_alias =
  let build_packages_of_context ctx_name =
    let open Action_builder.O in
    let* native_names, opam_targets =
      Action_builder.of_memo
        (let open Memo.O in
         let+ mounted = Pkg_sources.mounted ctx_name in
         List.fold_left
           mounted
           ~init:(Package.Name.Set.empty, [])
           ~f:(fun (native_names, opam_targets) mounted ->
             let candidate = Pkg_sources.Mounted.candidate mounted in
             let name = Pkg_sources.Candidate.name candidate in
             match Pkg_sources.Mounted.kind mounted with
             | Dune -> Package.Name.Set.add native_names name, opam_targets
             | Opam stanza ->
               let target =
                 Opam_stanza.target_dir
                   stanza
                   ~dir:(Pkg_sources.Candidate.artifact_root candidate)
                 |> Path.build
               in
               native_names, target :: opam_targets))
    in
    let* () = Action_builder.paths opam_targets in
    if Package.Name.Set.is_empty native_names
    then Action_builder.return ()
    else Install_layout.deps ctx_name native_names
  in
  fun ~dir ctx_name ->
    let rule =
      (* We only need to build when the build_dir is the root of the context *)
      match
        let build_dir = Context_name.build_dir ctx_name in
        Path.Build.equal dir build_dir
      with
      | false -> Memo.return Rules.empty
      | true ->
        let* active = Lock_dir.lock_dir_active ctx_name in
        let alias = Alias.make ~dir Alias0.pkg_install in
        Rules.collect_unit (fun () ->
          let deps =
            match active with
            | true -> build_packages_of_context ctx_name
            | false -> pkg_alias_disabled
          in
          Rules.Produce.Alias.add_deps alias deps)
    in
    Gen_rules.rules_for ~dir ~allowed_subdirs:Filename.Set.empty rule
    |> Gen_rules.rules_here
;;

let setup_dev_tool_package_rules db ~package_universe ~dir ~pkg_digest
  : Gen_rules.result Memo.t
  =
  let* pkg = Resolve.resolve db Loc.none pkg_digest package_universe in
  let paths = Paths.make pkg.pkg_digest package_universe ~relative:Path.Build.relative in
  let+ directory_targets =
    let map =
      let target_dir = paths.target_dir in
      Path.Build.Map.singleton target_dir Loc.none
    in
    match pkg.info.source with
    | None -> Memo.return map
    | Some source ->
      Lock_dir.source_kind source
      >>| (function
       | `Local (`Directory, _) -> map
       | `Local (`File, _) | `Fetch ->
         Path.Build.Map.add_exn map paths.source_dir (fst source.url))
  in
  let build_dir_only_sub_dirs =
    Gen_rules.Build_only_sub_dirs.singleton ~dir Subdir_set.empty
  in
  let context_name = Package_universe.context_name package_universe in
  let rules = Rules.collect_unit (fun () -> gen_dev_tool_rules context_name pkg) in
  Gen_rules.make ~directory_targets ~build_dir_only_sub_dirs rules
;;

let setup_rules ~components ~dir ctx =
  (* The string [.dev-tool] is hardcoded into several patterns and must match
     [Pkg_dev_tool.install_path_base_dir_name]. *)
  assert (String.equal Pkg_dev_tool.install_path_base_dir_name ".dev-tool");
  match Context_name.is_default ctx, components with
  | true, [ ".dev-tool"; ".pkg"; dev_tool_package_name; pkg_digest_string ] ->
    let pkg_name = Package.Name.of_string dev_tool_package_name in
    let dev_tool = Dune_pkg.Dev_tool.of_package_name pkg_name in
    let pkg_digest = Pkg_digest.of_string pkg_digest_string in
    let* db, _ = DB.of_dev_tool dev_tool in
    setup_dev_tool_package_rules
      db
      ~package_universe:(Dev_tool_dependency dev_tool)
      ~dir
      ~pkg_digest
  | true, [ ".dev-tool"; ".pkg" ]
  | true, [ ".dev-tool"; ".pkg"; _ ]
  | true, [ ".dev-tool" ] -> Gen_rules.make_empty ~dir Subdir_set.all |> Memo.return
  | true, [ ".dev-tool"; dev_tool_package_name ] ->
    let pkg_name = Package.Name.of_string dev_tool_package_name in
    let dev_tool = Dune_pkg.Dev_tool.of_package_name pkg_name in
    let* db, pkg_digest = DB.of_dev_tool dev_tool in
    setup_dev_tool_package_rules db ~package_universe:(Dev_tool dev_tool) ~dir ~pkg_digest
  | true, ".dev-tool" :: _ :: _ :: _ ->
    Memo.return @@ Gen_rules.redirect_to_parent Gen_rules.Rules.empty
  | is_default, [] ->
    let sub_dirs = if is_default then [ Filename.dev_tool_dir_basename ] else [] in
    let build_dir_only_sub_dirs =
      Gen_rules.Build_only_sub_dirs.singleton ~dir (Subdir_set.of_list sub_dirs)
    in
    Memo.return @@ Gen_rules.make ~build_dir_only_sub_dirs (Memo.return Rules.empty)
  | _ -> Memo.return @@ Gen_rules.rules_here Gen_rules.Rules.empty
;;

let mounted_dependencies context (stanza : Opam_stanza.t) =
  let+ packages = Mounted_packages.create context in
  let dependencies =
    List.filter_map (Package.depends stanza.package) ~f:(fun dependency ->
      let name = dependency.Package_dependency.name in
      if Package.Name.equal name Dune_pkg.Dune_dep.name
      then None
      else (
        match Mounted_packages.find packages name with
        | Some mounted -> Some mounted
        | None ->
          User_error.raise
            ~loc:stanza.loc
            [ Pp.textf "Package %s does not exist" (Package.Name.to_string name) ]))
  in
  packages, dependencies
;;

let gen_opam_rules context ~dir package_name =
  let* mounted = Pkg_sources.find_mounted context package_name in
  let mounted = Option.value_exn mounted in
  let candidate = Pkg_sources.Mounted.candidate mounted in
  if not (Path.Build.equal dir (Pkg_sources.Candidate.artifact_root candidate))
  then
    Code_error.raise
      "Synthetic opam stanza has an unexpected artifact root"
      [ "dir", Path.Build.to_dyn dir
      ; ( "artifact_root"
        , Pkg_sources.Candidate.artifact_root candidate |> Path.Build.to_dyn )
      ];
  let working_dir = Pkg_sources.Mounted.working_dir mounted in
  let stanza =
    match Pkg_sources.Mounted.kind mounted with
    | Dune ->
      Code_error.raise
        "Native package dispatched through synthetic opam rules"
        [ "package", Package.Name.to_dyn package_name ]
    | Opam stanza -> stanza
  in
  let lock_pkg = Pkg_sources.Candidate.lock_pkg candidate in
  let files_dir = Pkg_sources.Candidate.files_dir candidate in
  let _, paths = opam_paths mounted package_name in
  let source_kind = Pkg_sources.Mounted.source_kind mounted in
  let source =
    { Opam_package_rules.Source_input.root = working_dir
    ; kind =
        (match source_kind with
         | Primary_source -> Directory
         | No_source -> No_source)
    ; files_dir = Some files_dir
    ; extra_sources =
        List.map lock_pkg.info.extra_sources ~f:(fun (local, source) ->
          local, Fetch_rules.target source `File |> Path.build)
    }
  in
  let source_deps =
    match source_kind with
    | Primary_source -> Dep.Set.of_files [ Path.build working_dir ]
    | No_source -> Dep.Set.empty
  in
  let dependencies =
    let open Action_builder.O in
    let* packages, dependencies =
      Action_builder.of_memo (mounted_dependencies context stanza)
    in
    Mounted_packages.materialize_capabilities context packages dependencies
  in
  Opam_package_rules.gen_rules
    context
    stanza
    ~paths
    ~variables:(Package_deps.variables stanza.package)
    ~source
    ~source_deps
    ~dependencies
;;

let setup_mounted_opam_package_rules context mounted ~dir ~components =
  let candidate = Pkg_sources.Mounted.candidate mounted in
  let package_name = Pkg_sources.Candidate.name candidate in
  let package = Package.Name.to_string package_name in
  let artifact_root = Pkg_sources.Candidate.artifact_root candidate in
  let stanza =
    match Pkg_sources.Mounted.kind mounted with
    | Dune ->
      Code_error.raise
        "Native package dispatched through synthetic opam rules"
        [ "package", Package.Name.to_dyn package_name ]
    | Opam stanza -> stanza
  in
  match components with
  | [] ->
    let target = Opam_stanza.target_dir stanza ~dir:artifact_root |> Path.build in
    let rules =
      Rules.collect_unit (fun () ->
        Rules.Produce.Alias.add_deps
          (Alias.make Alias0.all ~dir:artifact_root)
          (Action_builder.path target))
    in
    let build_dir_only_sub_dirs =
      Gen_rules.Build_only_sub_dirs.singleton
        ~dir
        (Subdir_set.of_list [ Filename.of_string_exn ".opam" ])
    in
    Gen_rules.make ~build_dir_only_sub_dirs rules |> Memo.return
  | [ ".opam" ] ->
    Gen_rules.make_empty ~dir (Subdir_set.of_list [ Filename.of_string_exn package ])
    |> Memo.return
  | [ ".opam"; package' ] when String.equal package package' ->
    let target = Opam_stanza.target_dir stanza ~dir:artifact_root in
    let directory_targets = Path.Build.Map.singleton target Loc.none in
    let rules =
      Rules.collect_unit (fun () ->
        gen_opam_rules context ~dir:artifact_root package_name)
    in
    Gen_rules.make rules ~directory_targets |> Memo.return
  | _ -> Memo.return Gen_rules.no_rules
;;

let binaries_for_package context package =
  Memo.lazy_
    ~name:"package-dependency-binaries"
    ~human_readable_description:(fun () ->
      Pp.textf
        "Loading binaries for dependencies of package %S in context %S"
        (Package.Name.to_string package)
        (Context_name.to_string context))
    (fun () ->
       let* packages = Mounted_packages.create context in
       let dependencies =
         Mounted_packages.find_exn packages package
         |> Mounted_packages.dependencies
         |> Mounted_packages.capability_closure packages
       in
       Mounted_packages.binaries context dependencies)
;;

let ocaml_toolchain context =
  Memo.push_stack_frame ~human_readable_description:(fun () ->
    Pp.textf
      "Loading OCaml toolchain from Lock directory for context %S"
      (Context_name.to_string context))
  @@ fun () ->
  let* lock_dir = Lock_dir.get_exn context in
  match lock_dir.ocaml with
  | None -> Memo.return None
  | Some (_, ocaml) ->
    let* packages = Mounted_packages.create context in
    let closure = Mounted_packages.closure packages [ ocaml ] in
    let toolchain =
      let open Action_builder.O in
      let* materialized =
        Mounted_packages.materialize_capabilities context packages closure
      in
      let env = Env.extend_env (Global.env ()) (Package_deps.env materialized) in
      let { Package_deps.binaries; _ } = materialized in
      let binaries = Filename.Map.values binaries |> Path.Set.of_list in
      let path = Env_path.path (Global.env ()) in
      Action_builder.of_memo @@ Ocaml_toolchain.of_binaries ~path context env binaries
    in
    Some (Action_builder.memoize "ocaml_toolchain" toolchain) |> Memo.return
;;

let all_dev_tool_deps tool =
  let* db, pkg_digest = DB.of_dev_tool tool in
  let+ pkg = Resolve.resolve db Loc.none pkg_digest (Dev_tool tool) in
  Pkg.top_closure [ pkg ]
;;

let describe_packages = function
  | None -> "all packages"
  | Some packages ->
    Package.Name.Set.to_list packages
    |> List.map ~f:Package.Name.to_string
    |> String.concat ~sep:", "
;;

let lock_dir_binaries =
  Memo.create
    "lock-directory-binaries"
    ~input:
      (module struct
        type t = Context_name.t * Package.Name.Set.t option

        let to_dyn =
          Tuple.T2.to_dyn Context_name.to_dyn (Dyn.option Package.Name.Set.to_dyn)
        ;;

        let equal =
          Tuple.T2.equal Context_name.equal (Option.equal Package.Name.Set.equal)
        ;;

        let hash =
          let set_hash s = List.hash Package.Name.hash (Package.Name.Set.to_list s) in
          Tuple.T2.hash Context_name.hash (Option.hash set_hash)
        ;;
      end)
    ~human_readable_description:(fun (context, packages) ->
      Some
        (Pp.textf
           "Loading the binaries of %s in the lock directory for %S"
           (describe_packages packages)
           (Context_name.to_string context)))
    (fun (context, selected) ->
       let* packages = Mounted_packages.create context in
       Mounted_packages.selected packages selected |> Mounted_packages.binaries context)
;;

let package_binaries ~packages context = Memo.exec lock_dir_binaries (context, packages)

let which ~packages context program =
  let+ binaries = package_binaries ~packages context in
  Filename.Map.find binaries program
;;

let ocamlpath_of_deps deps =
  let env = Pkg.build_env_of_deps deps in
  Env.Map.find env Dune_findlib.Config.ocamlpath_var
  |> Option.value ~default:[]
  |> List.map ~f:(function
    | Value.Dir p | Path p -> p
    | String s -> Path.of_filename_relative_to_initial_cwd s)
;;

let project_ocamlpath context =
  let+ packages = Mounted_packages.create context in
  Package.Name.Map.values packages
  |> List.filter_map ~f:(fun mounted ->
    match Pkg_sources.Mounted.kind mounted with
    | Dune -> None
    | Opam stanza ->
      let name = Package.name stanza.package in
      let paths, _ = opam_paths mounted name in
      Some (Paths.install_roots paths).lib_root)
;;

module Opaque_libraries = struct
  type package =
    { name : Package.Name.t
    ; paths : Path.t Paths.t
    }

  type t =
    { by_name : package Package.Name.Map.t
    ; packages : package list
    }

  let for_package context package =
    Memo.push_stack_frame ~human_readable_description:(fun () ->
      Pp.textf
        "Loading opaque library dependencies of package %S"
        (Package.Name.to_string package))
    @@ fun () ->
    let+ mounted = Mounted_packages.create context in
    let packages =
      Mounted_packages.find_exn mounted package
      |> Mounted_packages.dependencies
      |> Mounted_packages.closure mounted
      |> List.filter_map ~f:(fun mounted ->
        match Pkg_sources.Mounted.kind mounted with
        | Dune -> None
        | Opam stanza ->
          let name = Package.name stanza.package in
          let paths, _ = opam_paths mounted name in
          Some { name; paths })
    in
    let by_name =
      Package.Name.Map.of_list_map_exn packages ~f:(fun package -> package.name, package)
    in
    { by_name; packages }
  ;;

  let paths package = [ (Paths.install_roots package.paths).lib_root ]
  let build package = Build_system.build_file (Paths.install_cookie package.paths)

  let find t package =
    match Package.Name.Map.find t.by_name package with
    | None -> Memo.return None
    | Some package ->
      let+ () = build package in
      Some (paths package)
  ;;

  let path_provides_library path package =
    let package = Package.Name.to_string package in
    let package_dir = Path.relative path package in
    Memo.List.exists
      [ Path.relative_fname package_dir Dune_findlib.Package.meta_fn
      ; Path.relative package_dir Dune_package.fn
      ; Path.relative path ("META." ^ package)
      ]
      ~f:Fs.file_exists
  ;;

  let find_provider t package =
    Memo.List.find_map t.packages ~f:(fun provider ->
      let* () = build provider in
      let paths = paths provider in
      let+ provides =
        Memo.List.exists paths ~f:(fun path -> path_provides_library path package)
      in
      if provides then Some paths else None)
  ;;

  let packages t = Package.Name.Map.keys t.by_name
end

let dev_tool_ocamlpath dev_tool =
  let+ deps = all_dev_tool_deps dev_tool in
  ocamlpath_of_deps deps
;;

let lock_dir_active = Lock_dir.lock_dir_active
let lock_dir_path = Lock_dir.get_path

let dev_tool_env tool =
  let package_name = Dune_pkg.Dev_tool.package_name tool in
  Memo.push_stack_frame ~human_readable_description:(fun () ->
    Pp.textf
      "lock directory environment for dev tools %S"
      (Package.Name.to_string package_name))
  @@ fun () ->
  let* db, pkg_digest = DB.of_dev_tool tool in
  let+ pkg = Resolve.resolve db Loc.none pkg_digest (Dev_tool tool) in
  Pkg.exported_env pkg
;;

let exported_env context =
  Memo.push_stack_frame ~human_readable_description:(fun () ->
    Pp.textf "lock directory environment for context %S" (Context_name.to_string context))
  @@ fun () ->
  let* mounted = Mounted_packages.create context in
  let packages = Package.Name.Map.keys mounted |> Mounted_packages.closure mounted in
  let+ materialized = Mounted_packages.environment context packages in
  Package_deps.env materialized
;;

let bin_path_env ~(packages : Package.Name.Set.t option) context =
  Memo.push_stack_frame ~human_readable_description:(fun () ->
    Pp.textf
      "lock directory PATH of %s for context %S"
      (describe_packages packages)
      (Context_name.to_string context))
  @@ fun () ->
  lock_dir_active context
  >>= function
  | false -> Memo.return Env.empty
  | true ->
    let* mounted = Mounted_packages.create context in
    let selected = Mounted_packages.selected mounted packages in
    let capabilities =
      List.map selected ~f:(fun package ->
        Mounted_packages.package package |> Package.name)
      |> Mounted_packages.capability_closure mounted
    in
    let+ materialized = Mounted_packages.environment context capabilities in
    (match Env.get (Package_deps.env materialized) Env_path.var with
     | None -> Env.empty
     | Some value -> Env.add Env.empty ~var:Env_path.var ~value)
;;

let all_filtered_depexts context =
  let* packages = Mounted_packages.create context in
  Package.Name.Map.values packages
  |> Memo.List.map ~f:(fun mounted ->
    let package = Mounted_packages.package mounted in
    let dependencies =
      Mounted_packages.dependencies mounted
      |> Mounted_packages.capability_closure packages
    in
    let* dependencies = Mounted_packages.environment context dependencies in
    let stanza, paths =
      match Pkg_sources.Mounted.kind mounted with
      | Opam stanza ->
        let paths, _ = opam_paths mounted (Package.name package) in
        stanza, paths
      | Dune ->
        let candidate = Pkg_sources.Mounted.candidate mounted in
        let lock_pkg = Pkg_sources.Candidate.lock_pkg candidate in
        let stanza =
          { Opam_stanza.loc = Loc.none
          ; origin = Lock
          ; package
          ; build = None
          ; install = None
          ; depexts = lock_pkg.depexts
          ; exported_env = []
          }
        in
        let install_root =
          Package.Name.Set.singleton (Package.name package)
          |> Install_layout.root context
          |> Path.build
        in
        stanza, Package_deps.Paths.of_local_package package ~install_root
    in
    Opam_package_rules.Action_expander.filtered_depexts_of_stanza
      context
      stanza
      ~paths
      ~variables:(Package_deps.variables package)
      dependencies)
  >>| List.concat
  >>| List.sort_uniq ~compare:String.compare
;;

let artifact_root_of_project_dependency context package_name =
  Pkg_sources.find_candidate context package_name
  >>| Option.map ~f:Pkg_sources.Candidate.artifact_root
;;
