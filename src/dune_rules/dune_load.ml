open Import
open Memo.O

module Dune_file_db = struct
  type t = Dune_file.t Path.Build.Map.t

  let make all =
    Path.Build.Map.of_list_map_exn all ~f:(fun dune_file ->
      Dune_file.output_dir dune_file, dune_file)
  ;;
end

let load = Dune_load_workspace.load

type loaded =
  { dune_files : Dune_file.t list
  ; projects_by_output_root : Loaded_project.t Path.Build.Map.t
  ; mounted_errors : User_message.t list Package.Name.Map.t
  }

module Mounted_dune_files =
  Source_tree.Rules.Dir.Make_map_reduce
    (Memo)
    (Monoid.Appendable_list (struct
         type t = Source_tree.Rules.Dir.t * Source.Dune_file.t
       end))

(* The projects and dune files of one partition of a context: the workspace,
   or one mounted package. *)
module Partition = struct
  type t =
    { projects_by_output_root : Loaded_project.t Path.Build.Map.t
    ; dune_files : Dune_file.t list
    ; dune_file_by_dir : Dune_file_db.t
    }

  let make projects dune_files =
    { projects_by_output_root =
        Path.Build.Map.of_list_map_exn projects ~f:(fun project ->
          Loaded_project.output_root project, project)
    ; dune_files
    ; dune_file_by_dir = Dune_file_db.make dune_files
    }
  ;;
end

let load_mount context mounted =
  let* _kind = Pkg_sources.Mounted.kind_exn mounted in
  let* projects, files =
    match Pkg_sources.Mounted.tree mounted with
    | None -> Memo.return ([], Appendable_list.empty)
    | Some tree ->
      let candidate = Pkg_sources.Mounted.candidate mounted in
      let owner = Pkg_sources.Candidate.name candidate in
      let artifact_root = Pkg_sources.Candidate.artifact_root candidate in
      let* projects =
        Pkg_sources.Mounted.projects mounted
        |> Memo.List.map ~f:(fun (project, source_tree_root) ->
          let* visible_packages =
            Dune_project.including_hidden_packages project
            |> Package.Name.Map.values
            |> Memo.List.filter ~f:(fun package ->
              if Package.Name.equal owner (Package.name package)
              then Dune_load_workspace.package_enabled package
              else Memo.return false)
            >>| Package.Name.Set.of_list_map ~f:Package.name
          in
          Loaded_project.create
            ~project
            ~mounted_package:(Some owner)
            ~source_tree_root
            ~context
            ~partition_root:artifact_root
            ~stanza_mask:(Some visible_packages)
          |> Memo.return)
      in
      let projects_by_root =
        Path.Local.Map.of_list_map_exn projects ~f:(fun project ->
          Loaded_project.source_root project, project)
      in
      let+ files =
        Mounted_dune_files.map_reduce
          (Source_tree.Rules.Mounted.root tree)
          ~traverse:Source_dir_status.Set.all
          ~trace_event_name:"Loaded mounted source tree"
          ~f:(fun dir ->
            match Source_tree.Rules.Dir.dune_file dir with
            | None -> Memo.return Appendable_list.empty
            | Some file -> Memo.return (Appendable_list.singleton (dir, file)))
      in
      let files =
        Appendable_list.map files ~f:(fun (dir, file) ->
          let root = Source_tree.Rules.Dir.project dir |> Dune_project.root in
          Path.Local.Map.find_exn projects_by_root root, dir, file)
      in
      projects, files
  in
  let* eval = Dune_file.eval files in
  let+ files = eval (Context.name context) in
  projects, files
;;

(* One node per locked package: loading a mounted package fetches its source, so
   only what asks for the package may force it. *)
let mount =
  let memo =
    Memo.create
      "mounted-package"
      ~input:
        (module struct
          type t = Context_name.t * Package.Name.t

          let to_dyn = Tuple.T2.to_dyn Context_name.to_dyn Package.Name.to_dyn
          let equal = Tuple.T2.equal Context_name.equal Package.Name.equal
          let hash = Tuple.T2.hash Context_name.hash Package.Name.hash
        end)
      (fun (context, name) ->
         let* mounted = Pkg_sources.find_mounted context name in
         match mounted with
         | None -> Memo.return None
         | Some mounted ->
           let* context = Context.DB.get context in
           let+ projects, dune_files = load_mount context mounted in
           Some (Partition.make projects dune_files))
  in
  fun context name -> Memo.exec memo (context, name)
;;

let load_mounted context =
  let* mounted = Pkg_sources.mounted context in
  Memo.List.map mounted ~f:(fun mounted ->
    let owner = Pkg_sources.Mounted.candidate mounted |> Pkg_sources.Candidate.name in
    let+ result =
      Memo.collect_user_errors (Memo.of_thunk (fun () -> mount context owner))
    in
    owner, result)
  >>| List.fold_left
        ~init:([], [], Package.Name.Map.empty)
        ~f:(fun (projects, files, errors) (name, result) ->
          match result with
          | Ok None -> projects, files, errors
          | Ok
              (Some
                 { Partition.projects_by_output_root; dune_files; dune_file_by_dir = _ })
            ->
            ( Path.Build.Map.values projects_by_output_root @ projects
            , dune_files @ files
            , errors )
          | Error messages ->
            projects, files, Package.Name.Map.add_exn errors name messages)
;;

let workspace =
  Per_context.create_by_name ~name:"workspace-loaded-projects" (fun context_name ->
    Memo.lazy_ ~name:"workspace-loaded-projects-for-context" (fun () ->
      let* workspace = load ()
      and* context = Context.DB.get context_name in
      let stanza_mask =
        match Only_packages.enumerate workspace.mask with
        | `All -> None
        | `Set names -> Some names
      in
      let projects =
        List.map workspace.projects ~f:(fun project ->
          Loaded_project.create
            ~project
            ~mounted_package:None
            ~source_tree_root:
              (Path.Local.Map.find_exn workspace.project_dirs (Dune_project.root project))
            ~context
            ~partition_root:(Context.build_dir context)
            ~stanza_mask)
      in
      let projects_by_root =
        Path.Local.Map.of_list_map_exn projects ~f:(fun project ->
          Loaded_project.source_root project, project)
      in
      let source_dune_files =
        Appendable_list.map workspace.dune_files ~f:(fun (dir, project, dune_file) ->
          let project =
            Path.Local.Map.find_exn projects_by_root (Dune_project.root project)
          in
          project, dir, dune_file)
      in
      let* eval = Dune_file.eval source_dune_files in
      let+ dune_files = eval context_name in
      Partition.make projects dune_files)
    |> Memo.Lazy.force)
  |> Staged.unstage
;;

let loaded =
  let by_context =
    Per_context.create_by_name ~name:"loaded-projects" (fun context_name ->
      Memo.lazy_ ~name:"loaded-projects-for-context" (fun () ->
        let* { Partition.projects_by_output_root; dune_files; dune_file_by_dir = _ } =
          workspace context_name
        in
        let projects = Path.Build.Map.values projects_by_output_root in
        let* mounted_projects, mounted_files, mounted_errors =
          load_mounted context_name
        in
        let projects = projects @ mounted_projects in
        let (_ : Package.t Package.Name.Map.t) =
          List.fold_left projects ~init:Package.Name.Map.empty ~f:(fun packages project ->
            Package.Name.Map.union
              packages
              (Loaded_project.packages project)
              ~f:(fun name first second ->
                User_error.raise
                  [ Pp.textf
                      "The package %S is defined more than once:"
                      (Package.Name.to_string name)
                  ; Pp.textf "- %s" (Loc.to_file_colon_line (Package.loc first))
                  ; Pp.textf "- %s" (Loc.to_file_colon_line (Package.loc second))
                  ]))
        in
        let dune_files = dune_files @ mounted_files in
        let projects_by_output_root =
          Path.Build.Map.of_list_map_exn projects ~f:(fun project ->
            Loaded_project.output_root project, project)
        in
        Memo.return { dune_files; projects_by_output_root; mounted_errors })
      |> Memo.Lazy.force)
    |> Staged.unstage
  in
  fun context -> by_context context
;;

let package_errors context =
  let+ { mounted_errors; _ } = loaded context in
  mounted_errors
;;

let check_package context name =
  let* { mounted_errors; _ } = loaded context in
  match Package.Name.Map.find mounted_errors name with
  | None -> Memo.return ()
  | Some messages ->
    Memo.parallel_iter messages ~f:(fun message -> raise (User_error.E message))
;;

let projects_by_output_root context =
  let+ { projects_by_output_root; _ } = loaded context in
  projects_by_output_root
;;

let packages_for_context context =
  let* workspace = load () in
  let+ projects = projects_by_output_root context in
  Path.Build.Map.fold projects ~init:workspace.packages ~f:(fun project packages ->
    if Loaded_project.is_workspace project
    then packages
    else Package.Name.Map.union_exn packages (Loaded_project.packages project))
;;

let context_of_dir dir =
  match Path.Build.extract_build_context dir with
  | Some (context, _) -> Context_name.of_string (Filename.to_string context)
  | None ->
    Code_error.raise
      "Dune_load: path is not in a build context"
      [ "dir", Path.Build.to_dyn dir ]
;;

let mount_of_dir context ~dir =
  match Pkg_sources.package_of_artifact_path dir with
  | None -> Memo.return None
  | Some package -> mount context package
;;

let find_loaded_project ~dir =
  let context = context_of_dir dir in
  let* mount = mount_of_dir context ~dir in
  let+ projects_by_output_root =
    match mount with
    | Some { Partition.projects_by_output_root; _ }
      when not (Path.Build.Map.is_empty projects_by_output_root) ->
      Memo.return projects_by_output_root
    | Some _ | None ->
      let+ { Partition.projects_by_output_root; _ } = workspace context in
      projects_by_output_root
  in
  Find_closest_source_dir.find_by_dir_exn projects_by_output_root ~dir
;;

let find_project ~dir =
  let+ project = find_loaded_project ~dir in
  Loaded_project.project project
;;

let stanzas_in_dir dir =
  if Path.Build.is_root dir
  then Memo.return None
  else (
    match Install.Context.of_path dir with
    | None -> Memo.return None
    | Some ctx ->
      let* mount = mount_of_dir ctx ~dir in
      (match mount with
       | Some { Partition.dune_file_by_dir; _ } ->
         Memo.return (Path.Build.Map.find dune_file_by_dir dir)
       | None ->
         let+ { Partition.dune_file_by_dir; _ } = workspace ctx in
         Path.Build.Map.find dune_file_by_dir dir))
;;

let mask () =
  let+ { mask; _ } = load () in
  mask
;;

let packages () =
  let+ { packages; _ } = load () in
  packages
;;

let package_closure_for_context context names =
  let* source_packages = packages_for_context context
  and* candidates = Pkg_sources.candidates context in
  let+ managed =
    Memo.List.map candidates ~f:(fun candidate ->
      let+ dependencies = Pkg_sources.Candidate.dependencies candidate in
      ( Pkg_sources.Candidate.name candidate
      , Package.Name.Set.remove dependencies Dune_pkg.Dune_dep.name ))
    >>| Package.Name.Map.of_list_exn
  in
  let rec loop acc name =
    if Package.Name.Set.mem acc name
    then acc
    else (
      let acc = Package.Name.Set.add acc name in
      let depends =
        match Package.Name.Map.find managed name with
        | Some depends -> depends
        | None ->
          (match Package.Name.Map.find source_packages name with
           | None -> Package.Name.Set.empty
           | Some package ->
             Package.depends package @ Package.depopts package
             |> Package.Name.Set.of_list_map ~f:(fun (dep : Package_dependency.t) ->
               dep.name))
      in
      Package.Name.Set.fold depends ~init:acc ~f:(fun name acc -> loop acc name))
  in
  Package.Name.Set.fold names ~init:Package.Name.Set.empty ~f:(fun name acc ->
    loop acc name)
;;

let dune_files context =
  let+ t = loaded context in
  t.dune_files
;;

let stanzas_of_package =
  let memo =
    Memo.create
      "stanzas-by-package"
      ~input:(module Context_name)
      (fun context ->
         let+ stanzas = dune_files context in
         Dune_file.fold_static_stanzas
           stanzas
           ~init:Package.Name.Map.empty
           ~f:(fun dune_file stanza acc ->
             let package =
               match Stanza.repr stanza with
               | Deprecated_library_name.T { old_name = old_public_name, _; _ } ->
                 Some (Package.id (Public_lib.package old_public_name))
               | _ -> Stanzas.stanza_package stanza
             in
             match package with
             | None -> acc
             | Some package ->
               Package.Name.Map.add_multi acc (Package.Id.name package) (dune_file, stanza))
         |> Package.Name.Map.map ~f:List.rev)
  in
  fun context package ->
    let+ stanzas = Memo.exec memo context in
    Package.Name.Map.Multi.find stanzas package
;;

let source_tree_root ~dir =
  match Path.Build.extract_build_context dir with
  | None -> Memo.return None
  | Some (context, _) ->
    let context = Context_name.of_string (Filename.to_string context) in
    let* valid = Per_context.valid context in
    if not valid
    then Memo.return None
    else (
      match Pkg_sources.package_of_artifact_path dir with
      | None ->
        Source_tree.root () >>| fun root -> Some (Source_tree.Rules.Dir.source root)
      | Some package ->
        let+ mounted = Pkg_sources.find_mounted context package in
        Option.bind mounted ~f:Pkg_sources.Mounted.tree
        |> Option.map ~f:Source_tree.Rules.Mounted.root)
;;

let source_tree_dir ~dir =
  let* root = source_tree_root ~dir in
  match root with
  | None -> Memo.return None
  | Some root ->
    let output_root =
      Source_tree.Rules.Dir.source_path root
      |> Path.Build.append_local (Context_name.build_dir (context_of_dir dir))
    in
    let local = Path.drop_prefix (Path.build dir) ~prefix:(Path.build output_root) in
    (match local with
     | None -> Memo.return None
     | Some local -> Source_tree.Rules.Dir.find_dir root local)
;;

let vendored_warnings ~dir =
  let* project = find_loaded_project ~dir in
  if Loaded_project.vendored_warnings project
  then Memo.return true
  else (
    let rec loop dir =
      let* source_dir = Loaded_project.source_tree_dir project dir in
      match source_dir with
      | Some dir ->
        Memo.return
          (match Source_tree.Rules.Dir.status dir with
           | Vendored -> true
           | Normal | Data_only -> false)
      | None ->
        (match Path.Build.parent dir with
         | None -> Memo.return false
         | Some dir -> loop dir)
    in
    loop dir)
;;

let projects () =
  let+ t = load () in
  t.projects
;;
