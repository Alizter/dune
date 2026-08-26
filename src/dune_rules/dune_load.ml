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
  { dune_files : (Source_path.t * Dune_project.t * Source.Dune_file.t) Appendable_list.t
  ; packages : Package.t Package.Name.Map.t
  ; projects : Dune_project.t list
  ; projects_by_root : Dune_project.t Source_path.Map.t
  ; mask : Only_packages.t
  }

type status =
  [ `Vendored
  | `Regular
  ]

module Projects_and_dune_files =
  Monoid.Product
    (Monoid.Appendable_list (struct
      type t = status * Dune_project.t
    end))
    (Monoid.Appendable_list (struct
         type t = Source_path.t * Dune_project.t * Source.Dune_file.t
       end))

module Rules_source_tree_map_reduce =
  Source_tree.Rules.Dir.Make_map_reduce (Memo) (Projects_and_dune_files)

module Loaded_dune_files = Monoid.Appendable_list (struct
    type t = Loaded_project.t * Source_path.t * Source.Dune_file.t
  end)

module Loaded_source_tree_map_reduce =
  Source_tree.Rules.Dir.Make_map_reduce (Memo) (Loaded_dune_files)

let load () =
  let status dir =
    match Source_tree.Rules.Dir.status dir with
    | Vendored -> `Vendored
    | Normal | Data_only -> `Regular
  in
  let* projects, dune_files =
    let f dir : Projects_and_dune_files.t Memo.t =
      let path = Source_tree.Rules.Dir.source_path dir in
      let project = Source_tree.Rules.Dir.project dir in
      let projects =
        if Source_path.equal path (Dune_project.root project)
        then Appendable_list.singleton (status dir, project)
        else Appendable_list.empty
      in
      let dune_files =
        match Source_tree.Rules.Dir.dune_file dir with
        | None -> Appendable_list.empty
        | Some d -> Appendable_list.singleton (path, project, d)
      in
      Memo.return (projects, dune_files)
    in
    let* root = Source_tree.root () in
    Rules_source_tree_map_reduce.map_reduce
      (Source_tree.Rules.Dir.source root)
      ~traverse:Source_dir_status.Set.all
      ~trace_event_name:"Dune load"
      ~f
  in
  let projects = Appendable_list.to_list_rev projects in
  let+ all_packages, vendored_packages =
    Memo.List.fold_left
      projects
      ~init:(Package.Name.Map.empty, Package.Name.Set.empty)
      ~f:(fun (acc_packages, vendored) (status, (project : Dune_project.t)) ->
        let+ packages =
          let packages = Dune_project.including_hidden_packages project in
          let+ disabled =
            Package.Name.Map.values packages
            |> Memo.List.filter_map ~f:(fun package ->
              let+ enabled = Package_enabled.eval package in
              Option.some_if (not enabled) package)
            >>| Package.Name.Map.of_list_map_exn ~f:(fun pkg -> Package.name pkg, ())
          in
          Package.Name.Map.merge packages disabled ~f:(fun _key package disabled ->
            match package, disabled with
            | Some p, Some () -> Some (p, `Disabled)
            | Some p, None -> Some (p, `Enabled)
            | None, None | None, Some _ -> assert false)
        in
        let vendored =
          match status with
          | `Regular -> vendored
          | `Vendored ->
            Package.Name.Set.of_keys packages |> Package.Name.Set.union vendored
        in
        let acc_packages =
          Package.Name.Map.union acc_packages packages ~f:(fun name (a, _) (b, _) ->
            User_error.raise
              [ Pp.textf
                  "The package %S is defined more than once:"
                  (Package.Name.to_string name)
              ; Pp.textf "- %s" (Loc.to_file_colon_line (Package.loc a))
              ; Pp.textf "- %s" (Loc.to_file_colon_line (Package.loc b))
              ])
        in
        acc_packages, vendored)
  in
  let mask = Only_packages.mask all_packages ~vendored:vendored_packages in
  let packages =
    Package.Name.Map.map ~f:fst all_packages |> Only_packages.filter_packages mask
  in
  let projects = List.rev_map projects ~f:snd in
  let projects_by_root =
    Source_path.Map.of_list_map_exn projects ~f:(fun project ->
      Dune_project.root project, project)
  in
  { dune_files; mask; packages; projects; projects_by_root }
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

let workspace_loaded_project context project =
  let source_root =
    Dune_project.root project |> Source_path.as_workspace |> Option.value_exn
  in
  let partition = Build_partition.workspace context in
  Loaded_project.create
    ~project
    ~identity:(Loaded_project.Identity.workspace source_root)
    ~source_root:(Source_path.workspace source_root)
    ~loaded_source:None
    ~partition
    ~output_root:(Path.Build.append_source (Context.build_dir context) source_root)
    ~visible_packages:None
;;

let mounted_loaded_project context mounted project =
  let candidate = Pkg_sources.Mounted.candidate mounted in
  let source = Pkg_sources.Mounted.source mounted in
  let package_source_root = Loaded_source.root source |> Source_path.build in
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
    ~loaded_source:(Some source)
    ~partition
    ~output_root:
      (Path.Build.append_local
         (Pkg_sources.Candidate.artifact_root candidate)
         project_root)
    ~visible_packages:
      (Some (Package.Name.Set.singleton (Pkg_sources.Candidate.name candidate)))
;;

let loaded =
  let by_context =
    Per_context.create_by_name ~name:"loaded-projects" (fun context_name ->
      Memo.Lazy.create ~name:"loaded-projects-for-context" (fun () ->
        let* workspace = load ()
        and* context = Context.DB.get context_name
        and* mounted = Pkg_sources.mounted context_name in
        let workspace_loaded_projects =
          List.map workspace.projects ~f:(workspace_loaded_project context)
        in
        let workspace_projects_by_root =
          Source_path.Map.of_list_map_exn workspace_loaded_projects ~f:(fun project ->
            Loaded_project.source_root project, project)
        in
        let mounted =
          List.map mounted ~f:(fun mounted ->
            let loaded_projects =
              List.map
                (Pkg_sources.Mounted.projects mounted)
                ~f:(mounted_loaded_project context mounted)
            in
            let projects_by_root =
              Source_path.Map.of_list_map_exn loaded_projects ~f:(fun project ->
                Loaded_project.source_root project, project)
            in
            mounted, loaded_projects, projects_by_root)
        in
        let loaded_projects =
          workspace_loaded_projects
          @ List.concat_map mounted ~f:(fun (_, projects, _) -> projects)
        in
        let projects_by_output_root =
          Path.Build.Map.of_list_map_exn loaded_projects ~f:(fun project ->
            Loaded_project.output_root project, project)
        in
        let workspace_dune_files =
          Appendable_list.map workspace.dune_files ~f:(fun (dir, project, dune_file) ->
            let loaded_project =
              Source_path.Map.find_exn
                workspace_projects_by_root
                (Dune_project.root project)
            in
            loaded_project, dir, dune_file)
        in
        let* mounted_dune_files =
          Memo.List.map mounted ~f:(fun (mounted, _, projects_by_root) ->
            let f dir =
              let project = Source_tree.Rules.Dir.project dir in
              let loaded_project =
                Source_path.Map.find_exn projects_by_root (Dune_project.root project)
              in
              let dune_files =
                match Source_tree.Rules.Dir.dune_file dir with
                | None -> Appendable_list.empty
                | Some dune_file ->
                  Appendable_list.singleton
                    (loaded_project, Source_tree.Rules.Dir.source_path dir, dune_file)
              in
              Memo.return dune_files
            in
            Loaded_source_tree_map_reduce.map_reduce
              (Pkg_sources.Mounted.tree mounted |> Source_tree.Rules.Loaded.root)
              ~traverse:Source_dir_status.Set.all
              ~trace_event_name:"Loaded source tree"
              ~f)
          >>| Appendable_list.concat
        in
        let source_dune_files =
          Appendable_list.concat [ workspace_dune_files; mounted_dune_files ]
        in
        let* eval = Dune_file.eval source_dune_files workspace.mask in
        let+ dune_files = eval context_name in
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
