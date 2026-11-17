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

module Context_and_package = struct
  type t = Context_name.t * Package.Name.t

  let to_dyn = Tuple.T2.to_dyn Context_name.to_dyn Package.Name.to_dyn
  let equal = Tuple.T2.equal Context_name.equal Package.Name.equal
  let hash = Tuple.T2.hash Context_name.hash Package.Name.hash
end

module Mounted_dune_files =
  Source_tree.Dir.Make_map_reduce
    (Memo)
    (Monoid.Product
       (Monoid.Appendable_list (struct
         type t = Dune_project.t * Source_tree.Dir.t
       end))
       (Monoid.Appendable_list (struct
            type t = Source_tree.Dir.t * Source.Dune_file.t
          end)))

(* The projects and dune files of one partition of a context: the workspace,
   or one mounted package. *)
module Partition = struct
  type t =
    { projects_by_output_root : Loaded_project.t Path.Build.Map.t
    ; dune_files : Dune_file.t list
    ; dune_file_by_dir : Dune_file_db.t
    }

  let make context_name projects dune_files =
    let projects_by_root =
      Path.Local.Map.of_list_map_exn projects ~f:(fun project ->
        Loaded_project.source_root project, project)
    in
    let* eval =
      Appendable_list.map dune_files ~f:(fun (dir, file) ->
        let root = Source_tree.Dir.project dir |> Dune_project.root in
        Path.Local.Map.find_exn projects_by_root root, dir, file)
      |> Dune_file.eval
    in
    let+ dune_files = eval context_name in
    { projects_by_output_root =
        Path.Build.Map.of_list_map_exn projects ~f:(fun project ->
          Loaded_project.output_root project, project)
    ; dune_files
    ; dune_file_by_dir = Dune_file_db.make dune_files
    }
  ;;

  let projects_by_output_root t = t.projects_by_output_root
  let dune_files t = t.dune_files
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
      let version = (Pkg_sources.Candidate.lock_pkg candidate).info.version in
      let* projects, files =
        Mounted_dune_files.map_reduce
          tree
          ~traverse:Source_dir_status.Set.all
          ~trace_event_name:"Loaded mounted source tree"
          ~f:(fun dir ->
            let project = Source_tree.Dir.project dir in
            Memo.return
              ( (if
                   Path.Local.equal
                     (Dune_project.root project)
                     (Source_tree.Dir.source_path dir)
                 then Appendable_list.singleton (project, dir)
                 else Appendable_list.empty)
              , match Source_tree.Dir.dune_file dir with
                | None -> Appendable_list.empty
                | Some file -> Appendable_list.singleton (dir, file) ))
      in
      let+ projects =
        Appendable_list.to_list projects
        |> Memo.List.map ~f:(fun (project, source_tree_root) ->
          let project =
            Dune_project.set_package_version project ~package:owner ~version
          in
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
            ~build_context:(Context.build_context context)
            ~partition_root:artifact_root
            ~stanza_mask:(Some visible_packages)
          |> Memo.return)
      in
      projects, files
  in
  Partition.make (Context.name context) projects files
;;

(* One node per locked package: loading a mounted package fetches its source, so
   only what asks for the package may force it. *)
let mount =
  let memo =
    Memo.create
      "mounted-package"
      ~input:(module Context_and_package)
      (fun (context, name) ->
         let* mounted = Pkg_sources.find_mounted context name in
         match mounted with
         | None -> Memo.return None
         | Some mounted ->
           let* context = Context.DB.get context in
           load_mount context mounted >>| Option.some)
  in
  fun context name -> Memo.exec memo (context, name)
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
        List.map workspace.projects ~f:(fun (project, dir) ->
          Loaded_project.create
            ~project
            ~mounted_package:None
            ~source_tree_root:dir
            ~build_context:(Context.build_context context)
            ~partition_root:(Context.build_dir context)
            ~stanza_mask)
      in
      Partition.make context_name projects workspace.dune_files)
    |> Memo.Lazy.force)
  |> Staged.unstage
;;

(* The errors of loading a mounted package, for lookups that report them
   without failing. *)
let package_errors context name =
  Memo.collect_user_errors (mount context name)
  >>| function
  | Ok _ -> []
  | Error messages -> messages
;;

let find_package context name =
  let* { packages; _ } = load () in
  match Package.Name.Map.find packages name with
  | Some _ as package -> Memo.return package
  | None ->
    mount context name
    >>| (function
     | None -> None
     | Some { Partition.projects_by_output_root; _ } ->
       Path.Build.Map.values projects_by_output_root
       |> List.find_map ~f:(fun project ->
         Package.Name.Map.find (Loaded_project.packages project) name))
;;

let partition_of_dir context ~dir =
  let* mount =
    match Pkg_sources.package_of_artifact_path dir with
    | None -> Memo.return None
    | Some package -> mount context package
  in
  match mount with
  | Some ({ Partition.projects_by_output_root; _ } as partition)
    when not (Path.Build.Map.is_empty projects_by_output_root) -> Memo.return partition
  | Some _ | None -> workspace context
;;

let find_loaded_project ~dir =
  let context = Install.Context.of_path dir |> Option.value_exn in
  let+ { Partition.projects_by_output_root; _ } = partition_of_dir context ~dir in
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
      let+ { Partition.dune_file_by_dir; _ } = partition_of_dir ctx ~dir in
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

let package_closure_for_context context names =
  let* source_packages = packages ()
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
  let+ { Partition.dune_files; _ } = workspace context in
  dune_files
;;

let stanzas_by_package dune_files =
  Dune_file.fold_static_stanzas
    dune_files
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
  |> Package.Name.Map.map ~f:List.rev
;;

let dune_files_of_package context package =
  let* { packages; _ } = load () in
  if Package.Name.Map.mem packages package
  then dune_files context
  else
    mount context package
    >>| function
    | None -> []
    | Some { Partition.dune_files; _ } -> dune_files
;;

let stanzas_of_package =
  let memo =
    Memo.create
      "stanzas-by-package"
      ~input:(module Context_name)
      (fun context -> dune_files context >>| stanzas_by_package)
  in
  fun context package ->
    let* { packages; _ } = load () in
    if Package.Name.Map.mem packages package
    then
      let+ stanzas = Memo.exec memo context in
      Package.Name.Map.Multi.find stanzas package
    else
      let+ dune_files = dune_files_of_package context package in
      Package.Name.Map.Multi.find (stanzas_by_package dune_files) package
;;

let source_tree_root ~dir =
  match Install.Context.of_path dir with
  | None -> Memo.return None
  | Some context ->
    let* valid = Per_context.valid context in
    if not valid
    then Memo.return None
    else (
      match Pkg_sources.package_of_artifact_path dir with
      | None -> Source_tree.root () >>| Option.some
      | Some package ->
        let+ mounted = Pkg_sources.find_mounted context package in
        Option.bind mounted ~f:Pkg_sources.Mounted.tree)
;;

let source_tree_dir ~dir =
  let* root = source_tree_root ~dir in
  match root with
  | None -> Memo.return None
  | Some root ->
    let output_root =
      Source_tree.Dir.source_path root
      |> Path.Build.append_local
           (Context_name.build_dir (Install.Context.of_path dir |> Option.value_exn))
    in
    let local = Path.drop_prefix (Path.build dir) ~prefix:(Path.build output_root) in
    (match local with
     | None -> Memo.return None
     | Some local -> Source_tree.Dir.find_dir root local)
;;

let source_files ~dir =
  source_tree_dir ~dir
  >>| function
  | None -> Path.Build.Set.empty
  | Some source_dir ->
    Source_tree.Dir.filenames source_dir
    |> Filename.Array.Set.to_list
    |> Path.Build.Set.of_list_map ~f:(Path.Build.relative_fname dir)
;;

let vendored_warnings ~dir =
  let* project = find_loaded_project ~dir in
  if Loaded_project.vendored_warnings project
  then Memo.return true
  else
    Loaded_project.source_tree_dir project dir
    >>| function
    | None -> false
    | Some d -> Source_tree.Dir.status d = Vendored
;;

let projects () =
  let+ t = load () in
  List.map t.projects ~f:fst
;;
