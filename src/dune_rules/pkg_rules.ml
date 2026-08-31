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

    (* Helper which is called when both tables have an entry with the same
       digest. This happens when two lock directories have a package in common
       and the transitive dependency closure of the package is identical in both
       lock directories. Here we assert that the packages and their immediate
       dependencies are identical as a sanity check. *)
    let union_check
          pkg_digest
          ({ pkg = pkg_a; deps = deps_a; has_dune_dep = _; pkg_digest = _ } as entry)
          { pkg = pkg_b; deps = deps_b; has_dune_dep = _; pkg_digest = _ }
      =
      if not (Pkg.equal (Pkg.remove_locs pkg_a) (Pkg.remove_locs pkg_b))
      then
        Code_error.raise
          "Two packages with the same pkg digest differ in their fields"
          [ "pkg_digest", Pkg_digest.to_dyn pkg_digest
          ; "pkg_a", Pkg.to_dyn pkg_a
          ; "pkg_b", Pkg.to_dyn pkg_b
          ];
      List.combine deps_a deps_b
      |> List.iter ~f:(fun (dep_a, dep_b) ->
        if not (Pkg.equal (Pkg.remove_locs dep_a.dep_pkg) (Pkg.remove_locs dep_b.dep_pkg))
        then
          Code_error.raise
            "Two packages with the same pkg digest differ in their dependencies"
            [ "pkg_digest", Pkg_digest.to_dyn pkg_digest
            ; "pkg_a", Pkg.to_dyn pkg_a
            ; "pkg_b", Pkg.to_dyn pkg_b
            ; "dep_of_a", Pkg.to_dyn dep_a.dep_pkg
            ; "dep_of_b", Pkg.to_dyn dep_b.dep_pkg
            ]);
      Some entry
    ;;

    let union = Pkg_digest.Map.union ~f:union_check
    let union_all = Pkg_digest.Map.union_all ~f:union_check
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

  type dev_tool_index =
    { dev_tool : Pkg_dev_tool.t
    ; key : Lock_dir_index_key.t
    ; index : Pkg_table.index
    }

  type existing_dev_tools =
    { indexes : dev_tool_index list
    ; combined : Pkg_table.t
    }

  let index_of_dev_tool_if_lock_dir_exists dev_tool ~platform =
    Lock_dir.of_dev_tool_if_lock_dir_exists dev_tool
    >>= function
    | None -> Memo.return None
    | Some lock_dir ->
      let path = Lock_dir.dev_tool_external_lock_dir dev_tool |> Path.external_ in
      let key = { Lock_dir_index_key.path; lock_dir; platform } in
      let+ index = lock_dir_index path lock_dir platform in
      Some { dev_tool; key; index }
  ;;

  let combined_dev_tool_indexes indexes =
    List.map indexes ~f:(fun { index; _ } -> index.Pkg_table.entries_by_digest)
    |> Pkg_table.union_all
  ;;

  let all_existing_dev_tools =
    Memo.lazy_ ~name:"all-existing-dev-tools" (fun () ->
      let* platform = Lock_dir.Sys_vars.solver_env in
      let+ indexes =
        Memo.List.map Pkg_dev_tool.all ~f:(index_of_dev_tool_if_lock_dir_exists ~platform)
        >>| List.filter_opt
      in
      { indexes; combined = combined_dev_tool_indexes indexes })
  ;;

  let find_existing_dev_tool { indexes; _ } dev_tool =
    List.find indexes ~f:(fun index -> Pkg_dev_tool.equal index.dev_tool dev_tool)
  ;;

  let replace_dev_tool_index indexes replacement =
    let rec loop = function
      | [] -> [ replacement ]
      | index :: indexes ->
        if Pkg_dev_tool.equal index.dev_tool replacement.dev_tool
        then replacement :: indexes
        else index :: loop indexes
    in
    loop indexes
  ;;

  let project_index =
    let memo =
      Memo.create
        "pkg-db-project-index"
        ~input:(module Context_name)
        (fun ctx ->
           let* path, lock_dir = Lock_dir.get_with_path ctx >>| User_error.ok_exn
           and* platform = Lock_dir.Sys_vars.solver_env in
           lock_dir_index path lock_dir platform)
    in
    fun ctx -> Memo.exec memo ctx
  ;;

  module Project_pkg_key = struct
    type t = Context_name.t * Package.Name.t

    let to_dyn = Tuple.T2.to_dyn Context_name.to_dyn Package.Name.to_dyn
    let hash = Tuple.T2.hash Context_name.hash Package.Name.hash
    let equal = Tuple.T2.equal Context_name.equal Package.Name.equal
  end

  let project_pkg_digest =
    let memo =
      Memo.create "pkg-db-project-package" ~input:(module Project_pkg_key)
      @@ fun (ctx, pkg_name) ->
      let+ index = project_index ctx in
      Pkg_table.find_digest_by_name index pkg_name
    in
    fun ctx pkg_name -> Memo.exec memo (ctx, pkg_name)
  ;;

  let of_ctx =
    let of_ctx_memo =
      Memo.create
        "pkg-db"
        ~input:
          (module struct
            type t = Context_name.t * bool

            let to_dyn = Tuple.T2.to_dyn Context_name.to_dyn Dyn.bool
            let hash = Tuple.T2.hash Context_name.hash Bool.hash
            let equal = Tuple.T2.equal Context_name.equal Bool.equal
          end)
        (fun (ctx, allow_sharing) ->
           Per_context.valid ctx
           >>= function
           | false ->
             Code_error.raise "invalid context" [ "context", Context_name.to_dyn ctx ]
           | true ->
             (* Dev tools are built in the default context, so allow their
                dependencies to be shared with the project's if it too is being
                built in the default context. *)
             let allow_sharing = allow_sharing && Context_name.is_default ctx in
             let* project_index = project_index ctx in
             let+ pkg_digest_table =
               if allow_sharing
               then
                 let+ existing_dev_tools = Memo.Lazy.force all_existing_dev_tools in
                 Pkg_table.union
                   project_index.Pkg_table.entries_by_digest
                   existing_dev_tools.combined
               else Memo.return project_index.Pkg_table.entries_by_digest
             in
             create ~pkg_digest_table)
    in
    fun ctx ~allow_sharing -> Memo.exec of_ctx_memo (ctx, allow_sharing)
  ;;

  (* Returns the db for the given context and the digest of the given package
     within that context. *)
  let of_project_pkg ctx pkg_name =
    let+ t = of_ctx ctx ~allow_sharing:true
    and+ pkg_digest = project_pkg_digest ctx pkg_name in
    t, Option.value_exn pkg_digest
  ;;

  (* Returns the db for all dev tools combined with the default context, and
     the digest for the dev tool's package. *)
  let of_dev_tool =
    let inactive_lockdir =
      Memo.lazy_ ~name:"inactive-lockdir-package-db" (fun () ->
        let+ existing_dev_tools = Memo.Lazy.force all_existing_dev_tools in
        create ~pkg_digest_table:existing_dev_tools.combined)
    in
    let memo =
      Memo.create "pkg-db-dev-tool" ~input:(module Dune_pkg.Dev_tool)
      @@ fun dev_tool ->
      let* existing_dev_tools = Memo.Lazy.force all_existing_dev_tools in
      let* lock_dir = Lock_dir.of_dev_tool dev_tool
      and* platform = Lock_dir.Sys_vars.solver_env in
      let path = Lock_dir.dev_tool_external_lock_dir dev_tool |> Path.external_ in
      let key = { Lock_dir_index_key.path; lock_dir; platform } in
      let* index = lock_dir_index path lock_dir platform in
      let current = { dev_tool; key; index } in
      let included_in_existing =
        match find_existing_dev_tool existing_dev_tools dev_tool with
        | None -> false
        | Some existing -> Lock_dir_index_key.equal existing.key key
      in
      let+ db =
        if included_in_existing
        then
          Lock_dir.lock_dir_active Context_name.default
          >>= function
          | false -> Memo.Lazy.force inactive_lockdir
          | true -> of_ctx Context_name.default ~allow_sharing:true
        else (
          let current_dev_tools =
            replace_dev_tool_index existing_dev_tools.indexes current
            |> combined_dev_tool_indexes
          in
          Lock_dir.lock_dir_active Context_name.default
          >>= function
          | false -> create ~pkg_digest_table:current_dev_tools |> Memo.return
          | true ->
            let+ project_index = project_index Context_name.default in
            create
              ~pkg_digest_table:
                (Pkg_table.union
                   project_index.Pkg_table.entries_by_digest
                   current_dev_tools))
      in
      db, Pkg_table.digest_by_name index (Pkg_dev_tool.package_name dev_tool)
    in
    fun dev_tool -> Memo.exec memo dev_tool
  ;;
end

let exact_mounted_package context (pkg : Pkg.t) =
  Pkg_sources.find_mounted context pkg.info.name
  >>= function
  | None -> Memo.return None
  | Some mounted ->
    let+ _, mounted_digest = DB.of_project_pkg context pkg.info.name in
    Option.some_if (Pkg_digest.equal pkg.pkg_digest mounted_digest) mounted
;;

let is_project_mounted_pkg context pkg =
  exact_mounted_package context pkg
  >>| function
  | Some mounted -> Pkg_sources.Mounted.is_dune mounted
  | None -> false
;;

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

let remap_opam_package context (pkg : Pkg.t) =
  exact_mounted_package context pkg
  >>| function
  | Some mounted ->
    (match Pkg_sources.Mounted.kind mounted with
     | Dune -> pkg
     | Opam _ ->
       let paths, write_paths = opam_paths mounted pkg.info.name in
       { pkg with paths; write_paths })
  | None -> pkg
;;

let dependency_view_for_package context (pkg : Pkg.t) =
  let* dependencies =
    Pkg.deps_closure pkg |> Memo.parallel_map ~f:(remap_opam_package context)
  in
  Dependency_view.of_list
    context
    dependencies
    ~is_mounted:(is_project_mounted_pkg context)
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
              | Dev_tool _ ->
                (* The dependencies of dev tools are installed into the default
                 context so they may be shared with the project's
                 dependencies. *)
                Package_universe.Dependencies Context_name.default
              | _ -> package_universe
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

let gen_rules context_name (pkg : Pkg.t) =
  let* dependencies =
    Dependency_view.make
      context_name
      pkg
      ~is_mounted:(is_project_mounted_pkg context_name)
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
  Opam_package_rules.gen_rules_legacy context_name pkg ~source ~source_deps ~dependencies
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
    (* Fetching the package target implies that we will also fetch the extra
       sources. *)
    let open Action_builder.O in
    let* pkg_digests, native_names, opam_targets =
      Action_builder.of_memo
        (let open Memo.O in
         let* db = DB.of_ctx ctx_name ~allow_sharing:true
         and* mounted = Pkg_sources.mounted ctx_name in
         let mounted_names, native_names, opam_targets =
           List.fold_left
             mounted
             ~init:(Package.Name.Set.empty, Package.Name.Set.empty, [])
             ~f:(fun (mounted_names, native_names, opam_targets) mounted ->
               let candidate = Pkg_sources.Mounted.candidate mounted in
               let name = Pkg_sources.Candidate.name candidate in
               let mounted_names = Package.Name.Set.add mounted_names name in
               match Pkg_sources.Mounted.kind mounted with
               | Dune ->
                 mounted_names, Package.Name.Set.add native_names name, opam_targets
               | Opam stanza ->
                 let target =
                   Opam_stanza.target_dir
                     stanza
                     ~dir:(Pkg_sources.Candidate.artifact_root candidate)
                   |> Path.build
                 in
                 mounted_names, native_names, target :: opam_targets)
         in
         let* mounted_digests =
           Memo.parallel_map (Package.Name.Set.to_list mounted_names) ~f:(fun name ->
             DB.of_project_pkg ctx_name name >>| snd)
         in
         let mounted_digests = Pkg_digest.Set.of_list mounted_digests in
         let pkg_digests =
           Pkg_digest.Map.keys db.pkg_digest_table
           |> List.filter ~f:(fun pkg_digest ->
             not (Pkg_digest.Set.mem mounted_digests pkg_digest))
         in
         Memo.return (pkg_digests, native_names, opam_targets))
    in
    let* () =
      List.map pkg_digests ~f:(fun pkg_digest ->
        Paths.make ~relative:Path.Build.relative pkg_digest (Dependencies ctx_name)
        |> Paths.target_dir
        |> Path.build)
      |> List.rev_append opam_targets
      |> Action_builder.paths
    in
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

let setup_package_rules db ~package_universe ~dir ~pkg_digest : Gen_rules.result Memo.t =
  let* pkg = Resolve.resolve db Loc.none pkg_digest package_universe in
  let* mounted =
    match package_universe with
    | Dev_tool _ -> Memo.return false
    | Dependencies context ->
      Pkg_sources.find_mounted context pkg.info.name
      >>= (function
       | None -> Memo.return false
       | Some mounted ->
         if not (Pkg_sources.Mounted.is_dune mounted)
         then Memo.return false
         else
           let+ _, mounted_digest = DB.of_project_pkg context pkg.info.name in
           Pkg_digest.equal pkg_digest mounted_digest)
  in
  if mounted
  then Memo.return Gen_rules.no_rules
  else (
    let paths =
      Paths.make pkg.pkg_digest package_universe ~relative:Path.Build.relative
    in
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
    let rules = Rules.collect_unit (fun () -> gen_rules context_name pkg) in
    Gen_rules.make ~directory_targets ~build_dir_only_sub_dirs rules)
;;

let setup_rules ~components ~dir ctx =
  (* Note that the path components in the following patterns must
     correspond to the paths returned by [Paths.make]. The string
     ".dev-tool" is hardcoded into several patterns, and must match
     the value of [Pkg_dev_tool.install_path_base_dir_name]. *)
  assert (String.equal Pkg_dev_tool.install_path_base_dir_name ".dev-tool");
  match Context_name.is_default ctx, components with
  | true, [ ".dev-tool"; dev_tool_package_name ] ->
    let pkg_name = Package.Name.of_string dev_tool_package_name in
    let dev_tool = Pkg_dev_tool.of_package_name pkg_name in
    let* db, pkg_digest = DB.of_dev_tool (Dune_pkg.Dev_tool.of_package_name pkg_name) in
    setup_package_rules db ~package_universe:(Dev_tool dev_tool) ~dir ~pkg_digest
  | true, [ ".dev-tool" ] -> Gen_rules.make_empty ~dir Subdir_set.all |> Memo.return
  | _, [ ".pkg" ] -> Gen_rules.make_empty ~dir Subdir_set.all |> Memo.return
  | _, [ ".pkg"; pkg_digest_string ] ->
    (* Only generate pkg rules if there is a lock dir for that context *)
    let* lock_dir_active = Lock_dir.lock_dir_active ctx in
    (match lock_dir_active with
     | false -> Memo.return @@ Gen_rules.make (Memo.return Rules.empty)
     | true ->
       let pkg_digest = Pkg_digest.of_string pkg_digest_string in
       let* db = DB.of_ctx ctx ~allow_sharing:true in
       setup_package_rules db ~package_universe:(Dependencies ctx) ~dir ~pkg_digest)
  | _, ".pkg" :: _ :: _ ->
    Memo.return @@ Gen_rules.redirect_to_parent Gen_rules.Rules.empty
  | true, ".dev-tool" :: _ :: _ :: _ ->
    Memo.return @@ Gen_rules.redirect_to_parent Gen_rules.Rules.empty
  | is_default, [] ->
    let sub_dirs =
      Filename.pkg_dir_basename
      :: (if is_default then [ Filename.dev_tool_dir_basename ] else [])
    in
    let build_dir_only_sub_dirs =
      Gen_rules.Build_only_sub_dirs.singleton ~dir @@ Subdir_set.of_list sub_dirs
    in
    Memo.return @@ Gen_rules.make ~build_dir_only_sub_dirs (Memo.return Rules.empty)
  | _ -> Memo.return @@ Gen_rules.rules_here Gen_rules.Rules.empty
;;

let resolve_pkg_dep context (loc, package_name) =
  let* db, pkg_digest = DB.of_project_pkg context package_name in
  Resolve.resolve db loc pkg_digest (Dependencies context)
;;

let gen_opam_rules context ~dir package_name =
  let* package = resolve_pkg_dep context (Loc.none, package_name)
  and* mounted = Pkg_sources.find_mounted context package_name in
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
  let* package = remap_opam_package context package in
  let* dependencies = dependency_view_for_package context package in
  let stanza =
    match Pkg_sources.Mounted.kind mounted with
    | Dune ->
      Code_error.raise
        "Native package dispatched through synthetic opam rules"
        [ "package", Package.Name.to_dyn package_name ]
    | Opam stanza -> stanza
  in
  let source_kind = Pkg_sources.Mounted.source_kind mounted in
  let source =
    { Opam_package_rules.Source_input.root = working_dir
    ; kind =
        (match source_kind with
         | Primary_source -> Directory
         | No_source -> No_source)
    ; files_dir = Some package.files_dir
    ; extra_sources =
        List.map package.info.extra_sources ~f:(fun (local, source) ->
          local, Fetch_rules.target source `File |> Path.build)
    }
  in
  let source_deps =
    match source_kind with
    | Primary_source -> Dep.Set.of_files [ Path.build working_dir ]
    | No_source -> Dep.Set.empty
  in
  let* () = Action_expander.refresh_exported_env context dependencies in
  Opam_package_rules.gen_rules
    context
    stanza
    ~paths:package.write_paths
    ~variables:(Pkg_info.variables package.info)
    ~source
    ~source_deps
    ~dependencies:(Action_expander.Artifacts_and_deps.materialize context dependencies)
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
       let* pkg = resolve_pkg_dep context (Loc.none, package) in
       let* dependencies = dependency_view_for_package context pkg in
       let* () = Action_expander.refresh_exported_env context dependencies in
       let+ { Action_expander.Artifacts_and_deps.binaries; dep_info = _ } =
         Action_expander.Artifacts_and_deps.of_dependency_view context dependencies
       in
       binaries)
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
  | Some ocaml ->
    let* pkg = resolve_pkg_dep context ocaml in
    let* transitive_deps =
      pkg :: Pkg.deps_closure pkg |> Memo.parallel_map ~f:(remap_opam_package context)
    in
    let toolchain =
      let open Action_builder.O in
      let* env, binaries =
        Action_builder.List.fold_left
          ~init:(Global.env (), Path.Set.empty)
          ~f:(fun (env, binaries) pkg ->
            let env = Env.extend_env env (Pkg.exported_env pkg) in
            let+ cookie = (Pkg_installed.of_paths pkg.paths).cookie in
            let binaries =
              Section.Map.find cookie.files Bin
              |> Option.value ~default:[]
              |> Path.Set.of_list
              |> Path.Set.union binaries
            in
            env, binaries)
          transitive_deps
      in
      let path = Env_path.path (Global.env ()) in
      Action_builder.of_memo @@ Ocaml_toolchain.of_binaries ~path context env binaries
    in
    Some (Action_builder.memoize "ocaml_toolchain" toolchain) |> Memo.return
;;

let all_deps universe =
  let* db =
    match (universe : Package_universe.t) with
    | Dependencies ctx ->
      (* Disallow sharing so that the only packages in the DB are the ones from
         the universe's respective lock directory. *)
      DB.of_ctx ctx ~allow_sharing:false
    | Dev_tool tool -> DB.of_dev_tool tool >>| fst
  in
  Pkg_digest.Map.values db.pkg_digest_table
  |> Memo.parallel_map ~f:(fun { DB.Pkg_table.pkg_digest; _ } ->
    Resolve.resolve db Loc.none pkg_digest universe)
  >>| Pkg.top_closure
;;

let all_project_deps context = all_deps (Dependencies context)

(* The packages of the lock directory reachable from [packages], or all of them
   when [packages] is [None]. [packages] holds the names visible to a directory,
   which include workspace packages; those are absent from the lock directory
   and so drop out of the filter. *)
let project_deps_closure ~(packages : Package.Name.Set.t option) context =
  let+ all_project_deps = all_project_deps context in
  match packages with
  | None -> all_project_deps
  | Some packages ->
    List.filter all_project_deps ~f:(fun (pkg : Pkg.t) ->
      Package.Name.Set.mem packages pkg.info.name)
    |> Pkg.top_closure
;;

let dependency_view context dependencies =
  let* dependencies = Memo.parallel_map dependencies ~f:(remap_opam_package context) in
  let* view =
    Dependency_view.of_list
      context
      dependencies
      ~is_mounted:(is_project_mounted_pkg context)
  in
  let+ () = Action_expander.refresh_exported_env context view in
  view
;;

let project_dependency_view ~packages context =
  let* dependencies = project_deps_closure ~packages context in
  dependency_view context dependencies
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
    (fun (context, packages) ->
       let* view = project_dependency_view ~packages context in
       let+ { Action_expander.Artifacts_and_deps.binaries; dep_info = _ } =
         Action_expander.Artifacts_and_deps.of_dependency_view context view
       in
       binaries)
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
  let+ view = project_dependency_view ~packages:None context in
  ocamlpath_of_deps view.legacy
;;

module Legacy_libraries = struct
  type t =
    { by_name : Pkg.t Package.Name.Map.t
    ; packages : Pkg.t list
    }

  let make context packages =
    let* dependencies = dependency_view context packages in
    let packages = dependencies.legacy in
    let by_name =
      Package.Name.Map.of_list_map_exn packages ~f:(fun (pkg : Pkg.t) ->
        pkg.info.name, pkg)
    in
    Memo.return { by_name; packages }
  ;;

  let for_package context package =
    Memo.push_stack_frame ~human_readable_description:(fun () ->
      Pp.textf
        "Loading legacy library dependencies of package %S"
        (Package.Name.to_string package))
    @@ fun () ->
    let* pkg = resolve_pkg_dep context (Loc.none, package) in
    make context (Pkg.deps_closure pkg)
  ;;

  let find t package =
    match Package.Name.Map.find t.by_name package with
    | None -> Memo.return None
    | Some (pkg : Pkg.t) ->
      let* () = Build_system.build_file (Paths.install_cookie pkg.paths) in
      Memo.return (Some (ocamlpath_of_deps [ pkg ]))
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
    Memo.List.find_map t.packages ~f:(fun (pkg : Pkg.t) ->
      let* () = Build_system.build_file (Paths.install_cookie pkg.paths) in
      let paths = ocamlpath_of_deps [ pkg ] in
      let+ provides =
        Memo.List.exists paths ~f:(fun path -> path_provides_library path package)
      in
      if provides then Some paths else None)
  ;;

  let packages t = Package.Name.Map.keys t.by_name
end

let dev_tool_ocamlpath dev_tool =
  let+ deps = all_deps (Dev_tool dev_tool) in
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
  let+ view = project_dependency_view ~packages:None context in
  let env = Pkg.build_env_of_deps view.all in
  let vars = Env.Map.map env ~f:Value_list_env.string_of_env_values in
  Env.extend Env.empty ~vars
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
    let+ view = project_dependency_view ~packages context in
    let env = Pkg.build_env_of_deps view.all in
    (match Env.Map.find env Env_path.var with
     | None -> Env.empty
     | Some values ->
       Env.add
         Env.empty
         ~var:Env_path.var
         ~value:(Value_list_env.string_of_env_values values))
;;

let find_package context package =
  lock_dir_active context
  >>= function
  | false -> Memo.return None
  | true ->
    let* package = resolve_pkg_dep context (Loc.none, package) in
    let+ package = remap_opam_package context package in
    Some
      (let open Action_builder.O in
       let+ _cookie = (Pkg_installed.of_paths package.paths).cookie in
       ())
;;

let resolve_installed_file ~loc ~context_name ~pkg_name ~section ~file =
  let open Action_builder.O in
  let* { paths; _ } =
    Action_builder.of_memo
      (Memo.bind
         (resolve_pkg_dep context_name (loc, pkg_name))
         ~f:(fun package -> remap_opam_package context_name package))
  in
  let* { files; _ } = (Pkg_installed.of_paths paths).cookie in
  let section_dir =
    let install_paths = Lazy.force paths.install_paths in
    Install.Paths.get install_paths section
  in
  let path = Path.append_local section_dir file in
  let installed = Section.Map.find files section |> Option.value ~default:[] in
  match List.exists installed ~f:(Path.equal path) with
  | true ->
    let+ () = Action_builder.path path in
    path
  | false ->
    let file_str = Path.Local.to_string file in
    let candidates =
      List.filter_map installed ~f:(Path.drop_prefix ~prefix:section_dir)
      |> List.map ~f:Path.Local.to_string
    in
    User_error.raise
      ~loc
      ~hints:(User_message.did_you_mean file_str ~candidates)
      [ Pp.textf
          "File %s not found in section %s of package %s"
          file_str
          (Section.to_string section)
          (Package.Name.to_string pkg_name)
      ]
;;

let all_filtered_depexts context =
  let* all_project_deps = all_project_deps context in
  Memo.List.map all_project_deps ~f:(fun (pkg : Pkg.t) ->
    let* dependencies = dependency_view_for_package context pkg in
    let* () = Action_expander.refresh_exported_env context dependencies in
    let expander = Action_expander.expander context pkg dependencies in
    Action_expander.Expander.filtered_depexts expander)
  >>| List.concat
  >>| List.sort_uniq ~compare:String.compare
;;

let pkg_digest_of_project_dependency ctx package_name =
  let* _ = DB.of_ctx ctx ~allow_sharing:false in
  DB.project_pkg_digest ctx package_name
;;
