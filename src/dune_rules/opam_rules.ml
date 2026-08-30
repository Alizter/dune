open Import
open Memo.O
module Package_rules = Opam_package_rules
module Pkg = Package_rules.Pkg
module Paths = Package_rules.Paths
module Install_cookie = Package_rules.Install_cookie
module Pkg_installed = Package_rules.Pkg_installed
module Dependency_view = Package_rules.Dependency_view
module Action_expander = Package_rules.Action_expander
module Value_list_env = Package_rules.Value_list_env

type entry =
  { stanza : Opam_stanza.t
  ; output_dir : Path.Build.t
  }

let make_paths name output_dir stanza =
  let target_dir = Opam_stanza.target_dir stanza ~dir:output_dir in
  let root = Path.Build.parent_exn target_dir in
  let paths = Paths.of_root name ~root ~relative:Path.Build.relative in
  { paths with source_dir = output_dir; target_dir }
;;

let make_pkg context { stanza; output_dir } depends =
  let name = Package.name stanza.package in
  let version =
    Package.version stanza.package
    |> Option.value ~default:Dune_pkg.Lock_dir.Pkg_info.default_version
  in
  let write_paths = make_paths name output_dir stanza in
  let paths = Paths.map_path write_paths ~f:Path.build in
  let info =
    { Dune_pkg.Lock_dir.Pkg_info.name
    ; version
    ; dev = false
    ; avoid = false
    ; source = None
    ; extra_sources = []
    }
  in
  let pkg_digest =
    { Package_rules.Pkg_digest.name
    ; version
    ; lockfile_and_dependency_digest =
        Dune_digest.string
          (Path.Build.to_string output_dir ^ ":" ^ Package.Name.to_string name)
    }
  in
  let pkg =
    { Pkg.id = Pkg.Id.gen ()
    ; build_command = stanza.build
    ; install_command = stanza.install
    ; depends
    ; depends_on_dune =
        List.exists depends ~f:(fun (dependency : Pkg.t) ->
          Package.Name.equal dependency.info.name Dune_pkg.Dune_dep.name)
    ; depexts = stanza.depexts
    ; info
    ; paths
    ; write_paths
    ; files_dir =
        Path.Build.relative (Path.Build.parent_exn write_paths.target_dir) "files"
    ; pkg_digest
    ; unexpanded_exported_env = stanza.exported_env
    ; exported_env = []
    }
  in
  let* dependencies =
    Dependency_view.of_list context (Pkg.deps_closure pkg) ~is_mounted:(fun _ ->
      Memo.return false)
  in
  let* () = Action_expander.refresh_exported_env context dependencies in
  let expander = Action_expander.expander context pkg dependencies in
  let+ exported_env =
    Memo.parallel_map stanza.exported_env ~f:(Action_expander.exported_env expander)
  in
  pkg.exported_env <- exported_env;
  pkg
;;

let entries =
  Per_context.create_by_name ~name:"opam-stanza-entries" (fun context ->
    Memo.lazy_ ~name:"opam-stanza-entries" (fun () ->
      let* dune_files = Dune_load.workspace_dune_files context in
      let+ entries =
        Memo.List.concat_map dune_files ~f:(fun dune_file ->
          let+ stanzas = Dune_file.find_stanzas dune_file Opam_stanza.key in
          List.map stanzas ~f:(fun (stanza : Opam_stanza.t) ->
            ( Package.name stanza.package
            , { stanza; output_dir = Dune_file.output_dir dune_file } )))
      in
      Package.Name.Map.of_list_reduce entries ~f:(fun first second ->
        User_error.raise
          ~loc:second.stanza.loc
          [ Pp.textf
              "Package %s has more than one opam stanza"
              (Package.Name.to_string (Package.name second.stanza.package))
          ; Pp.textf "The first stanza is at %s" (Loc.to_file_colon_line first.stanza.loc)
          ]))
    |> Memo.Lazy.force)
  |> Staged.unstage
;;

let package_names context =
  let+ entries = entries context in
  Package.Name.Map.keys entries |> Package.Name.Set.of_list
;;

let packages =
  Per_context.create_by_name ~name:"opam-stanza-packages" (fun context ->
    Memo.lazy_ ~name:"opam-stanza-packages" (fun () ->
      let* entries = entries context in
      let rec resolve resolved stack (loc, name) =
        match Package.Name.Map.find resolved name with
        | Some package -> Memo.return (resolved, package)
        | None ->
          (match Package.Name.Map.find entries name with
           | None ->
             User_error.raise
               ~loc
               [ Pp.textf
                   "Package %s is not provided by an opam stanza"
                   (Package.Name.to_string name)
               ]
           | Some entry ->
             if Package.Name.Set.mem stack name
             then
               User_error.raise
                 ~loc
                 [ Pp.text "The following opam stanzas form a dependency cycle:"
                 ; Pp.chain
                     (Package.Name.Set.to_list (Package.Name.Set.add stack name))
                     ~f:(fun name -> Pp.verbatim (Package.Name.to_string name))
                 ]
             else (
               let stack = Package.Name.Set.add stack name in
               let* resolved, depends =
                 Memo.List.fold_left
                   entry.stanza.depends
                   ~init:(resolved, [])
                   ~f:(fun (resolved, depends) dependency ->
                     let+ resolved, package = resolve resolved stack dependency in
                     resolved, package :: depends)
               in
               let* package = make_pkg context entry (List.rev depends) in
               let resolved = Package.Name.Map.add_exn resolved name package in
               Memo.return (resolved, package)))
      in
      Package.Name.Map.to_list entries
      |> Memo.List.fold_left
           ~init:Package.Name.Map.empty
           ~f:(fun resolved (name, entry) ->
             let+ resolved, _ =
               resolve resolved Package.Name.Set.empty (entry.stanza.loc, name)
             in
             resolved))
    |> Memo.Lazy.force)
  |> Staged.unstage
;;

let selected_packages context selected =
  let+ packages = packages context in
  Package.Name.Map.values packages
  |> List.filter ~f:(fun (package : Pkg.t) ->
    match selected with
    | None -> true
    | Some selected -> Package.Name.Set.mem selected package.info.name)
  |> Pkg.top_closure
;;

let dependency_view context (pkg : Pkg.t) =
  Dependency_view.of_list context (Pkg.deps_closure pkg) ~is_mounted:(fun _ ->
    Memo.return false)
;;

let gen_rules context ~dir stanza =
  let package_name = Package.name stanza.Opam_stanza.package in
  let* target =
    match stanza.origin with
    | User ->
      let* packages = packages context in
      let package = Package.Name.Map.find_exn packages package_name in
      let* source_deps, _source_files = Source_deps.files package.paths.source_dir in
      let* dependencies = dependency_view context package in
      let source =
        { Package_rules.Source_input.root = package.write_paths.source_dir
        ; files_dir = None
        ; extra_sources = []
        }
      in
      let+ () =
        Package_rules.gen_rules context package ~source ~source_deps ~dependencies
      in
      package.paths.target_dir
    | Lock ->
      let+ () = Pkg_rules.gen_opam_rules context ~dir package_name in
      Opam_stanza.target_dir stanza ~dir |> Path.build
  in
  Rules.Produce.Alias.add_deps (Alias.make Alias0.all ~dir) (Action_builder.path target)
;;

let find_package context name =
  let+ packages = packages context in
  Package.Name.Map.find packages name
  |> Option.map ~f:(fun (package : Pkg.t) ->
    let open Action_builder.O in
    let+ _ = (Pkg_installed.of_paths package.paths).cookie in
    ())
;;

let resolve_stanza_installed_file context name ~loc ~section ~file =
  let package =
    let open Memo.O in
    let+ packages = packages context in
    Package.Name.Map.find_exn packages name
  in
  let open Action_builder.O in
  let* package = Action_builder.of_memo package in
  let* ({ files; _ } : Install_cookie.t) =
    (Pkg_installed.of_paths package.paths).cookie
  in
  let section_dir = Install.Paths.get (Paths.install_paths package.paths) section in
  let path = Path.append_local section_dir file in
  let installed = Section.Map.find files section |> Option.value ~default:[] in
  if List.exists installed ~f:(Path.equal path)
  then
    let+ () = Action_builder.path path in
    path
  else (
    let file = Path.Local.to_string file in
    let candidates =
      List.filter_map installed ~f:(Path.drop_prefix ~prefix:section_dir)
      |> List.map ~f:Path.Local.to_string
    in
    User_error.raise
      ~loc
      ~hints:(User_message.did_you_mean file ~candidates)
      [ Pp.textf
          "File %s not found in section %s of package %s"
          file
          (Section.to_string section)
          (Package.Name.to_string name)
      ])
;;

let resolve_installed_file context name ~loc ~section ~file =
  let open Action_builder.O in
  let* mounted = Action_builder.of_memo (Pkg_sources.find_mounted context name) in
  match mounted with
  | Some mounted ->
    (match Pkg_sources.Mounted.kind mounted with
     | Opam _ ->
       Pkg_rules.resolve_installed_file
         ~loc
         ~context_name:context
         ~pkg_name:name
         ~section
         ~file
     | Dune -> resolve_stanza_installed_file context name ~loc ~section ~file)
  | None -> resolve_stanza_installed_file context name ~loc ~section ~file
;;

let binaries_of_package (package : Pkg.t) =
  let cookie = (Pkg_installed.of_paths package.paths).cookie in
  Action_builder.evaluate_and_collect_facts cookie
  >>| fun ((cookie : Install_cookie.t), _) ->
  Section.Map.Multi.find cookie.files Bin
  |> List.fold_left ~init:Filename.Map.empty ~f:(fun binaries path ->
    let name =
      Path.basename path |> Filename.to_string |> Bin.strip_exe |> Filename.of_string_exn
    in
    Filename.Map.set binaries name path)
;;

let binaries context ~packages:selected =
  let* packages = selected_packages context selected in
  let+ binaries = Memo.parallel_map packages ~f:binaries_of_package in
  Filename.Map.union_all binaries ~f:(fun _name first _second -> Some first)
;;

let exported_env context ~packages:selected =
  let+ packages = selected_packages context selected in
  let variables =
    Pkg.build_env_of_deps packages |> Env.Map.map ~f:Value_list_env.string_of_env_values
  in
  Env.extend Env.empty ~vars:variables
;;

let libraries context package_names ~parent =
  let context_name = Context.name context in
  let candidates =
    let+ packages = packages context_name in
    List.filter_map package_names ~f:(Package.Name.Map.find packages) |> Pkg.top_closure
  in
  let db_ref = Fdecl.create Dyn.opaque in
  let db_for_package (package : Pkg.t) =
    let cookie = (Pkg_installed.of_paths package.paths).cookie in
    let* (cookie : Install_cookie.t), _ =
      Action_builder.evaluate_and_collect_facts cookie
    in
    match Section.Map.find cookie.files Lib, Section.Map.find cookie.files Lib_root with
    | None, None -> Memo.return None
    | Some [], None | None, Some [] | Some [], Some [] -> Memo.return None
    | _ ->
      let path = (Paths.install_roots package.paths).lib_root in
      let+ db = Lib.DB.of_paths context ~paths:[ path ] in
      Some db
  in
  let databases =
    Memo.lazy_ ~name:"opam-stanza-library-databases" (fun () ->
      let* candidates = candidates in
      Memo.parallel_map candidates ~f:db_for_package)
    |> Memo.Lazy.force
  in
  let resolve name =
    let* databases = databases in
    Memo.List.find_map databases ~f:(fun db ->
      Memo.Option.bind db ~f:(fun db ->
        let+ available = Lib.DB.available db name in
        Option.some_if available (Lib.DB.with_parent db ~parent:(Fdecl.get db_ref))))
    >>| function
    | None -> Lib.DB.Resolve_result.not_found
    | Some db -> Lib.DB.Resolve_result.redirect_by_name db (Loc.none, name)
  in
  let db =
    Lib.DB.create
      ~parent:(Some parent)
      ~resolve:(fun name ->
        let+ result = resolve name in
        [ result ])
      ~resolve_lib_id:(fun id -> resolve (Lib_id.name id))
      ~all:(fun () ->
        let* databases = databases in
        let+ names =
          Memo.List.concat_map databases ~f:(function
            | None -> Memo.return []
            | Some db ->
              let+ libraries = Lib.DB.all db ~recursive:false in
              Lib.Set.to_list_map libraries ~f:Lib.name)
        in
        List.sort_uniq names ~compare:Lib_name.compare)
      ~instrument_with:(Context.instrument_with context)
      ()
  in
  Fdecl.set db_ref db;
  db
;;
