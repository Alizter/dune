open Import
open Memo.O
module Package_rules = Opam_package_rules
module Paths = Package_rules.Paths
module Install_cookie = Package_rules.Install_cookie
module Action_expander = Package_rules.Action_expander

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

let write_paths { stanza; output_dir } =
  make_paths (Package.name stanza.package) output_dir stanza
;;

let read_paths entry = write_paths entry |> Paths.map_path ~f:Path.build

let package_variables { stanza; _ } =
  let name = Package.name stanza.package in
  let version =
    Package.version stanza.package
    |> Option.value ~default:Dune_pkg.Lock_dir.Pkg_info.default_version
  in
  Package_variable_name.Map.of_list_exn
    [ Package_variable_name.name, Package_deps.Variable.S (Package.Name.to_string name)
    ; Package_variable_name.version, S (Package_version.to_string version)
    ; Package_variable_name.dev, B false
    ]
;;

let closure entries roots =
  let rec visit ~loc name visiting visited ordered =
    if Package.Name.Set.mem visited name
    then visited, ordered
    else if Package.Name.Set.mem visiting name
    then
      User_error.raise
        ~loc
        [ Pp.text "The following opam stanzas form a dependency cycle:"
        ; Pp.chain
            (Package.Name.Set.to_list (Package.Name.Set.add visiting name))
            ~f:(fun name -> Pp.verbatim (Package.Name.to_string name))
        ]
    else (
      let entry =
        match Package.Name.Map.find entries name with
        | Some entry -> entry
        | None ->
          User_error.raise
            ~loc
            [ Pp.textf
                "Package %s is not provided by an opam stanza"
                (Package.Name.to_string name)
            ]
      in
      let visiting = Package.Name.Set.add visiting name in
      let visited, ordered =
        List.fold_left
          (Package.depends entry.stanza.package)
          ~init:(visited, ordered)
          ~f:(fun (visited, ordered) dependency ->
            visit
              ~loc:entry.stanza.loc
              dependency.Package_dependency.name
              visiting
              visited
              ordered)
      in
      Package.Name.Set.add visited name, entry :: ordered)
  in
  let _, ordered =
    List.fold_left
      roots
      ~init:(Package.Name.Set.empty, [])
      ~f:(fun (visited, ordered) entry ->
        let name = Package.name entry.stanza.package in
        visit ~loc:entry.stanza.loc name Package.Name.Set.empty visited ordered)
  in
  List.rev ordered
;;

let dependency_entries entries entry =
  let name = Package.name entry.stanza.package in
  closure entries [ entry ]
  |> List.filter ~f:(fun dependency ->
    not (Package.Name.equal name (Package.name dependency.stanza.package)))
;;

let selected_entries entries selected =
  let roots =
    Package.Name.Map.values entries
    |> List.filter ~f:(fun entry ->
      match selected with
      | None -> true
      | Some selected -> Package.Name.Set.mem selected (Package.name entry.stanza.package))
  in
  closure entries roots
;;

let cookie entry =
  let open Action_builder.O in
  let paths = read_paths entry in
  let path = Paths.install_cookie paths in
  let+ () = Action_builder.dep (Dep.file path) in
  Install_cookie.load_exn path
;;

let materialize context entries =
  let open Action_builder.O in
  Action_builder.List.fold_left
    entries
    ~init:Package_deps.empty
    ~f:(fun materialized entry ->
      let paths = read_paths entry in
      let* () = Action_builder.dep (Dep.file paths.target_dir) in
      let cookie = Install_cookie.load_exn (Paths.install_cookie paths) in
      let variables =
        Package_variable_name.Map.superpose
          (Package_variable_name.Map.of_list_exn cookie.variables)
          (package_variables entry)
      in
      let* exported_env =
        Action_builder.of_memo
          (Action_expander.exported_env_of_stanza
             context
             entry.stanza
             ~paths
             ~variables
             materialized)
      in
      Action_builder.return
        (Package_deps.add_package
           materialized
           ~paths
           ~variables
           ~files:cookie.files
           ~exported_env))
;;

let gen_rules context ~dir stanza =
  let package_name = Package.name stanza.Opam_stanza.package in
  let* target =
    match stanza.origin with
    | User ->
      let* entries = entries context in
      let entry = Package.Name.Map.find_exn entries package_name in
      let write_paths = write_paths entry in
      let read_paths = Paths.map_path write_paths ~f:Path.build in
      let* source_deps, _source_files = Source_deps.files read_paths.source_dir in
      let source =
        { Package_rules.Source_input.root = write_paths.source_dir
        ; kind = Directory
        ; files_dir = None
        ; extra_sources = []
        }
      in
      let+ () =
        Package_rules.gen_rules
          context
          stanza
          ~paths:write_paths
          ~variables:(package_variables entry)
          ~source
          ~source_deps
          ~dependencies:(materialize context (dependency_entries entries entry))
      in
      read_paths.target_dir
    | Lock ->
      let+ () = Pkg_rules.gen_opam_rules context ~dir package_name in
      Opam_stanza.target_dir stanza ~dir |> Path.build
  in
  Rules.Produce.Alias.add_deps (Alias.make Alias0.all ~dir) (Action_builder.path target)
;;

let find_package context name =
  let+ entries = entries context in
  Package.Name.Map.find entries name
  |> Option.map ~f:(fun entry ->
    let open Action_builder.O in
    let+ _ = cookie entry in
    ())
;;

let resolve_stanza_installed_file context name ~loc ~section ~file =
  let open Action_builder.O in
  let* entry =
    Action_builder.of_memo
      (let open Memo.O in
       let+ entries = entries context in
       Package.Name.Map.find_exn entries name)
  in
  let* ({ files; _ } : Install_cookie.t) = cookie entry in
  let paths = read_paths entry in
  let section_dir = Install.Paths.get (Paths.install_paths paths) section in
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

let materialize_selected context selected =
  let* entries = entries context in
  materialize context (selected_entries entries selected)
  |> Action_builder.evaluate_and_collect_facts
  >>| fst
;;

let binaries context ~packages:selected =
  let+ materialized = materialize_selected context selected in
  materialized.Package_deps.binaries
;;

let exported_env context ~packages:selected =
  let+ materialized = materialize_selected context selected in
  materialized.Package_deps.env
;;

let libraries context package_names ~parent =
  let context_name = Context.name context in
  let candidates =
    let+ entries = entries context_name in
    let selected = Package.Name.Set.of_list package_names in
    selected_entries entries (Some selected)
  in
  let db_ref = Fdecl.create Dyn.opaque in
  let db_for_package entry =
    let* (cookie : Install_cookie.t), _ =
      cookie entry |> Action_builder.evaluate_and_collect_facts
    in
    match Section.Map.find cookie.files Lib, Section.Map.find cookie.files Lib_root with
    | None, None -> Memo.return None
    | Some [], None | None, Some [] | Some [], Some [] -> Memo.return None
    | _ ->
      let path = (Paths.install_roots (read_paths entry)).lib_root in
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
