open Import
open Memo.O

module Dune_file_db = struct
  type t = Dune_file.t Path.Build.Map.t

  let make all =
    Path.Build.Map.of_list_map_exn all ~f:(fun dune_file ->
      Dune_file.output_dir dune_file, dune_file)
  ;;
end

type t =
  { dune_files :
      (Source_tree.Rules.Dir.t * Dune_project.t * Source.Dune_file.t) Appendable_list.t
  ; packages : Package.t Package.Name.Map.t
  ; packages_including_hidden : Package.t Package.Name.Map.t
  ; projects : Dune_project.t list
  ; project_dirs : Source_tree.Rules.Dir.t Source_path.Map.t
  ; projects_by_root : Dune_project.t Source_path.Map.t
  ; mask : Only_packages.t
  ; package_scope : Package_scope.t
  }

type status =
  [ `Vendored
  | `Regular
  ]

module Projects_and_dune_files =
  Monoid.Product3
    (Monoid.Appendable_list (struct
      type t = status * Dune_project.t * Source_tree.Rules.Dir.t
    end))
    (Monoid.Appendable_list (struct
         type t = Source_tree.Rules.Dir.t * Dune_project.t * Source.Dune_file.t
       end))
    (Monoid.Appendable_list (struct
         type t = Source_path.t * Dune_lang.Scope_stanza.t
       end))

module Rules_source_tree_map_reduce =
  Source_tree.Rules.Dir.Make_map_reduce (Memo) (Projects_and_dune_files)

module Mounted_source =
  Monoid.Product
    (Monoid.Appendable_list (struct
      type t = Source_tree.Rules.Dir.t * Source.Dune_file.t
    end))
    (Monoid.Appendable_list (struct
         type t = Source_path.t * Dune_lang.Scope_stanza.t
       end))

module Build_source_tree_map_reduce =
  Source_tree.Rules.Dir.Make_map_reduce (Memo) (Mounted_source)

let load () =
  let status dir =
    match Source_tree.Rules.Dir.status dir with
    | Vendored -> `Vendored
    | Normal | Data_only -> `Regular
  in
  let* projects, dune_files, scopes =
    let f dir : Projects_and_dune_files.t Memo.t =
      let path = Source_tree.Rules.Dir.source_path dir in
      let project = Source_tree.Rules.Dir.project dir in
      let projects =
        if Source_path.equal path (Dune_project.root project)
        then Appendable_list.singleton (status dir, project, dir)
        else Appendable_list.empty
      in
      let dune_files, scopes =
        match Source_tree.Rules.Dir.dune_file dir with
        | None -> Appendable_list.empty, Appendable_list.empty
        | Some dune_file ->
          let scopes =
            match Source.Dune_file.scope dune_file with
            | None -> Appendable_list.empty
            | Some scope -> Appendable_list.singleton (path, scope)
          in
          Appendable_list.singleton (dir, project, dune_file), scopes
      in
      Memo.return (projects, dune_files, scopes)
    in
    let* root = Source_tree.root () in
    Rules_source_tree_map_reduce.map_reduce
      (Source_tree.Rules.Dir.source root)
      ~traverse:Source_dir_status.Set.all
      ~trace_event_name:"Dune load"
      ~f
  in
  let projects = Appendable_list.to_list_rev projects in
  let* package_entries =
    Memo.List.concat_map projects ~f:(fun (source_status, project, _) ->
      Dune_project.including_hidden_packages project
      |> Package.Name.Map.values
      |> Memo.List.map ~f:(fun package ->
        let+ enabled = Package_enabled.eval package in
        package, (if enabled then `Enabled else `Disabled), source_status))
  in
  let package_scope =
    Package_scope.create
      ~scopes:(Appendable_list.to_list_rev scopes)
      ~packages:(List.map package_entries ~f:(fun (package, _, _) -> package))
  in
  let package_entries =
    if Package_scope.is_empty package_scope
    then package_entries
    else
      List.filter package_entries ~f:(fun (package, _, _) ->
        Package_scope.is_package_visible package_scope package)
  in
  let all_packages, vendored_packages =
    List.fold_left
      package_entries
      ~init:(Package.Name.Map.empty, Package.Name.Set.empty)
      ~f:(fun (packages, vendored) (package, enabled, source_status) ->
        let name = Package.name package in
        let packages =
          Package.Name.Map.update packages name ~f:(function
            | None -> Some (package, enabled)
            | Some (previous, _) ->
              User_error.raise
                [ Pp.textf
                    "The package %S is defined more than once:"
                    (Package.Name.to_string name)
                ; Pp.textf "- %s" (Loc.to_file_colon_line (Package.loc previous))
                ; Pp.textf "- %s" (Loc.to_file_colon_line (Package.loc package))
                ])
        in
        let vendored =
          match source_status with
          | `Regular -> vendored
          | `Vendored -> Package.Name.Set.add vendored name
        in
        packages, vendored)
  in
  let packages_including_hidden = Package.Name.Map.map all_packages ~f:fst in
  let mask = Only_packages.mask all_packages ~vendored:vendored_packages in
  let packages = Only_packages.filter_packages mask packages_including_hidden in
  let project_dirs =
    Source_path.Map.of_list_map_exn projects ~f:(fun (_, project, dir) ->
      Dune_project.root project, dir)
  in
  let projects =
    List.rev_map projects ~f:(fun (_, project, _) ->
      Package_scope.filter_project package_scope project)
  in
  let projects_by_root =
    Source_path.Map.of_list_map_exn projects ~f:(fun project ->
      Dune_project.root project, project)
  in
  Memo.return
    { dune_files
    ; mask
    ; packages
    ; packages_including_hidden
    ; projects
    ; project_dirs
    ; projects_by_root
    ; package_scope
    }
;;

let load =
  let memo = Memo.lazy_ ~name:"dune_load" load in
  fun () -> Memo.Lazy.force memo
;;

type loaded =
  { dune_files : Dune_file.t list
  ; loaded_projects : Loaded_project.t list
  ; projects_by_output_root : Loaded_project.t Path.Build.Map.t
  ; dune_file_by_dir : Dune_file_db.t
  }

let workspace_loaded_project context package_scope project source_tree_root =
  let source_root =
    Dune_project.root project |> Source_path.as_workspace |> Option.value_exn
  in
  let partition = Build_partition.workspace context in
  Loaded_project.create
    ~project
    ~identity:(Loaded_project.Identity.workspace source_root)
    ~source_root:(Source_path.workspace source_root)
    ~source_tree_root
    ~partition
    ~output_root:(Path.Build.append_source (Context.build_dir context) source_root)
    ~package_view:(Loaded_project.Package_view.workspace package_scope)
;;

let packages_of_projects projects =
  List.concat_map projects ~f:(fun (project, _) ->
    Dune_project.including_hidden_packages project |> Package.Name.Map.values)
;;

let mounted_package_owner mounted projects =
  let package_name =
    Pkg_sources.Mounted.candidate mounted |> Pkg_sources.Candidate.name
  in
  match
    List.filter_map projects ~f:(fun (project, _) ->
      Package.Name.Map.find (Dune_project.including_hidden_packages project) package_name
      |> Option.map ~f:(fun package -> package, project))
  with
  | [ owner ] -> owner
  | [] ->
    Code_error.raise
      "Mounted source does not define its package"
      [ "package", Package.Name.to_dyn package_name ]
  | owners ->
    Code_error.raise
      "Mounted source defines its package in multiple projects"
      [ "package", Package.Name.to_dyn package_name
      ; "owners", Dyn.list Package.to_dyn (List.map owners ~f:fst)
      ]
;;

let mounted_project_package_scope ~selected_package_names mounted project =
  let package_name =
    Pkg_sources.Mounted.candidate mounted |> Pkg_sources.Candidate.name
  in
  let packages =
    Dune_project.including_hidden_packages project |> Package.Name.Map.values
  in
  let+ enabled_packages =
    Memo.List.filter packages ~f:(fun package -> Package_enabled.eval package)
  in
  let visible_packages =
    List.fold_left
      enabled_packages
      ~init:Package.Name.Set.empty
      ~f:(fun visible package ->
        let name = Package.name package in
        if
          Package.Name.equal name package_name
          || not (Package.Name.Set.mem selected_package_names name)
        then Package.Name.Set.add visible name
        else visible)
  in
  let scope = Dune_lang.Scope_stanza.make ~loc:Loc.none ~packages:visible_packages in
  Package_scope.create ~scopes:[ Dune_project.root project, scope ] ~packages
;;

let mounted_loaded_project context mounted ~package_view (project, source_tree_root) =
  let candidate = Pkg_sources.Mounted.candidate mounted in
  let package_source_root =
    Pkg_sources.Mounted.working_dir mounted |> Source_path.build
  in
  let source_root = Dune_project.root project in
  let project_root =
    Source_path.descendant source_root ~of_:package_source_root |> Option.value_exn
  in
  let partition =
    Build_partition.mounted
      ~resolver:context
      ~output_root:(Pkg_sources.Candidate.artifact_root candidate)
  in
  Loaded_project.create
    ~project
    ~identity:
      (Loaded_project.Identity.mounted
         ~lock:(Pkg_sources.Candidate.identity_digest candidate)
         ~package:(Pkg_sources.Candidate.name candidate)
         ~project_root)
    ~source_root
    ~source_tree_root
    ~partition
    ~output_root:
      (Path.Build.append_local
         (Pkg_sources.Candidate.artifact_root candidate)
         project_root)
    ~package_view
;;

type workspace_loaded =
  { dune_files : Dune_file.t list
  ; loaded_projects : Loaded_project.t list
  ; mask : Only_packages.t
  }

let workspace_loaded =
  let by_context =
    Per_context.create_by_name ~name:"workspace-loaded-projects" (fun context_name ->
      Memo.Lazy.create ~name:"workspace-loaded-projects-for-context" (fun () ->
        let* workspace = load ()
        and* context = Context.DB.get context_name in
        let loaded_projects =
          List.map workspace.projects ~f:(fun project ->
            let source_tree_root =
              Source_path.Map.find_exn workspace.project_dirs (Dune_project.root project)
            in
            workspace_loaded_project
              context
              workspace.package_scope
              project
              source_tree_root)
        in
        let projects_by_root =
          Source_path.Map.of_list_map_exn loaded_projects ~f:(fun project ->
            Loaded_project.source_root project, project)
        in
        let source_dune_files =
          Appendable_list.map
            workspace.dune_files
            ~f:(fun (source_dir, project, dune_file) ->
              let loaded_project =
                Source_path.Map.find_exn projects_by_root (Dune_project.root project)
              in
              loaded_project, source_dir, dune_file)
        in
        let* eval = Dune_file.eval source_dune_files workspace.mask in
        let+ dune_files = eval context_name in
        { dune_files; loaded_projects; mask = workspace.mask })
      |> Memo.Lazy.force)
    |> Staged.unstage
  in
  fun context -> by_context context
;;

let loaded =
  let by_context =
    Per_context.create_by_name ~name:"loaded-projects" (fun context_name ->
      Memo.Lazy.create ~name:"loaded-projects-for-context" (fun () ->
        let* workspace = workspace_loaded context_name
        and* context = Context.DB.get context_name
        and* mounted = Pkg_sources.mounted context_name
        and* selected_package_names = Pkg_sources.selected_package_names context_name in
        let mounted = List.filter mounted ~f:Pkg_sources.Mounted.is_dune in
        let* mounted =
          Memo.List.filter_map mounted ~f:(fun mounted ->
            match Pkg_sources.Mounted.tree mounted with
            | None -> Memo.return None
            | Some tree ->
              let candidate = Pkg_sources.Mounted.candidate mounted in
              let start = Time.now () in
              let f dir =
                let dune_files, scopes =
                  match Source_tree.Rules.Dir.dune_file dir with
                  | None -> Appendable_list.empty, Appendable_list.empty
                  | Some dune_file ->
                    let scopes =
                      match Source.Dune_file.scope dune_file with
                      | None -> Appendable_list.empty
                      | Some scope ->
                        Appendable_list.singleton
                          (Source_tree.Rules.Dir.source_path dir, scope)
                    in
                    Appendable_list.singleton (dir, dune_file), scopes
                in
                Memo.return (dune_files, scopes)
              in
              let* source_dune_files, scopes =
                Build_source_tree_map_reduce.map_reduce
                  (Source_tree.Rules.Build.root tree)
                  ~traverse:Source_dir_status.Set.all
                  ~trace_event_name:"Loaded source tree"
                  ~f
              in
              let projects = Pkg_sources.Mounted.projects mounted in
              let owner_package, owner_project = mounted_package_owner mounted projects in
              let source_package_scope =
                Package_scope.create
                  ~scopes:(Appendable_list.to_list_rev scopes)
                  ~packages:(packages_of_projects projects)
              in
              let* loaded_projects =
                Memo.List.map projects ~f:(fun ((project, _) as project_with_root) ->
                  let* synthetic_scope =
                    mounted_project_package_scope ~selected_package_names mounted project
                  in
                  let package_scope =
                    Package_scope.intersect source_package_scope synthetic_scope
                  in
                  let package_view =
                    Loaded_project.Package_view.mounted
                      ~package_scope
                      ~owner_package
                      ~owner_project
                  in
                  mounted_loaded_project context mounted ~package_view project_with_root
                  |> Memo.return)
              in
              let projects_by_root =
                Source_path.Map.of_list_map_exn loaded_projects ~f:(fun project ->
                  Loaded_project.source_root project, project)
              in
              let source_dune_files =
                Appendable_list.map source_dune_files ~f:(fun (dir, dune_file) ->
                  let project = Source_tree.Rules.Dir.project dir in
                  let loaded_project =
                    Source_path.Map.find_exn projects_by_root (Dune_project.root project)
                  in
                  loaded_project, dir, dune_file)
              in
              Dune_trace.emit Rules (fun () ->
                Dune_trace.Event.mounted_dune_load
                  ~start
                  ~stop:(Time.now ())
                  ~context:(Context_name.to_string context_name)
                  ~package:(Pkg_sources.Candidate.name candidate |> Package.Name.to_string)
                  ~source_root:(Pkg_sources.Mounted.working_dir mounted)
                  ~artifact_root:(Pkg_sources.Candidate.artifact_root candidate));
              Memo.return
                (Some (mounted, loaded_projects, projects_by_root, source_dune_files)))
        in
        let loaded_projects =
          workspace.loaded_projects
          @ List.concat_map mounted ~f:(fun (_, projects, _, _) -> projects)
        in
        let projects_by_output_root =
          Path.Build.Map.of_list_map_exn loaded_projects ~f:(fun project ->
            Loaded_project.output_root project, project)
        in
        let mounted_source_dune_files =
          List.map mounted ~f:(fun (_, _, _, dune_files) -> dune_files)
          |> Appendable_list.concat
        in
        let* eval = Dune_file.eval mounted_source_dune_files workspace.mask in
        let+ mounted_dune_files = eval context_name in
        let dune_files = workspace.dune_files @ mounted_dune_files in
        { dune_files
        ; loaded_projects
        ; projects_by_output_root
        ; dune_file_by_dir = Dune_file_db.make dune_files
        })
      |> Memo.Lazy.force)
    |> Staged.unstage
  in
  fun context -> by_context context
;;

let workspace_dune_files context =
  let+ loaded = workspace_loaded context in
  loaded.dune_files
;;

let context_of_dir dir =
  match Path.Build.extract_build_context dir with
  | Some (context, source_dir) ->
    let context = Context_name.of_string (Filename.to_string context) in
    if Context_name.equal context Private_context.t.name
    then (
      match Path.Source.explode source_dir with
      | context :: _ -> Context_name.of_string (Filename.to_string context)
      | [] ->
        Code_error.raise
          "Dune_load: private path has no resolver context"
          [ "dir", Path.Build.to_dyn dir ])
    else Option.value (Mounted_context.resolver context) ~default:context
  | None ->
    Code_error.raise
      "Dune_load: path is not in a build context"
      [ "dir", Path.Build.to_dyn dir ]
;;

let find_loaded_project ~dir =
  let context = context_of_dir dir in
  let+ { projects_by_output_root; _ } = loaded context in
  let rec loop dir =
    match Path.Build.Map.find projects_by_output_root dir with
    | Some project -> project
    | None ->
      (match Path.Build.parent dir with
       | Some parent -> loop parent
       | None ->
         Code_error.raise
           "Dune_load: no enclosing loaded project"
           [ "dir", Path.Build.to_dyn dir ])
  in
  loop dir
;;

let find_loaded_project_by_identity ~context ~identity =
  let+ { loaded_projects; _ } = loaded context in
  match
    List.find loaded_projects ~f:(fun project ->
      Loaded_project.Identity.equal (Loaded_project.identity project) identity)
  with
  | Some project -> project
  | None ->
    Code_error.raise
      "Dune_load: loaded project identity not found in context"
      [ "context", Context_name.to_dyn context
      ; "identity", Loaded_project.Identity.to_dyn identity
      ]
;;

let find_project ~dir =
  let+ project = find_loaded_project ~dir in
  Loaded_project.project project
;;

let is_vendored ~dir =
  let* loaded_project = find_loaded_project ~dir in
  match Build_partition.purpose (Loaded_project.partition loaded_project) with
  | Mounted -> Memo.return true
  | Workspace ->
    (match Path.Build.drop_build_context dir with
     | None -> Memo.return false
     | Some source_dir -> Source_tree.is_vendored source_dir)
;;

let stanzas_in_dir dir =
  if Path.Build.is_root dir
  then Memo.return None
  else (
    match Install.Context.of_path dir with
    | None -> Memo.return None
    | Some context ->
      let context = Option.value (Mounted_context.resolver context) ~default:context in
      let+ { dune_file_by_dir; _ } = loaded context in
      Path.Build.Map.find dune_file_by_dir dir)
;;

let mask () =
  let+ { mask; _ } = load () in
  mask
;;

let packages () =
  let+ { packages; _ } = load () in
  packages
;;

let packages_including_hidden () =
  let+ { packages_including_hidden; _ } = load () in
  packages_including_hidden
;;

let dune_files context =
  let+ loaded = loaded context in
  loaded.dune_files
;;

let loaded_projects context =
  let+ loaded = loaded context in
  loaded.loaded_projects
;;

let workspace_projects_by_root () =
  let+ t = load () in
  t.projects_by_root
;;

let projects () =
  let+ t = load () in
  t.projects
;;
