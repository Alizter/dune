open Import
open Memo.O

module Dune_file_db = struct
  type t = Dune_file.t Path.Source.Map.t

  let make all =
    Path.Source.Map.of_list_map_exn all ~f:(fun dune_file ->
      Dune_file.dir dune_file, dune_file)
  ;;
end

(** Information that is computed per build context, by walking that context's
    [Source_tree.t]. *)
module Ctx_data = struct
  type t =
    { dune_files : Dune_file.t list
    ; packages : Package.t Package.Name.Map.t
    ; projects : Dune_project.t list
    ; projects_by_root : Dune_project.t Path.Source.Map.t
    ; dune_file_by_dir : Dune_file_db.t
    ; mask : Only_packages.t
    }
end

type t = { ctx_data : Context_name.t -> Ctx_data.t Memo.t }

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
         type t = Path.Source.t * Dune_project.t * Source.Dune_file.t
       end))

module Source_tree_map_reduce =
  Source_tree.Make_map_reduce_with_progress (Memo) (Projects_and_dune_files)

let load_for_context_impl ctx =
  let status dir =
    match Source_tree.Dir.status dir with
    | Vendored -> `Vendored
    | Normal | Data_only -> `Regular
  in
  let* source_tree = Source_tree.for_context ctx in
  let* projects, dune_files =
    let f dir : Projects_and_dune_files.t Memo.t =
      let path = Source_tree.Dir.path dir in
      let project = Source_tree.Dir.project dir in
      let projects =
        if Path.Source.equal path (Dune_project.root project)
        then Appendable_list.singleton (status dir, project)
        else Appendable_list.empty
      in
      let dune_files =
        match Source_tree.Dir.dune_file dir with
        | None -> Appendable_list.empty
        | Some d -> Appendable_list.singleton (path, project, d)
      in
      Memo.return (projects, dune_files)
    in
    Source_tree_map_reduce.map_reduce
      source_tree
      ~traverse:Source_dir_status.Set.all
      ~trace_event_name:"Dune load"
      ~f
  in
  let projects = Appendable_list.to_list_rev projects in
  let* all_packages, vendored_packages =
    Memo.List.fold_left
      projects
      ~init:(Package.Name.Map.empty, Package.Name.Set.empty)
      ~f:(fun (acc_packages, vendored) (status, (project : Dune_project.t)) ->
        let+ packages =
          let packages = Dune_project.including_hidden_packages project in
          let+ disabled =
            Package.Name.Map.values packages
            |> List.filter_map ~f:(fun package ->
              Package.enabled_if package |> Option.map ~f:(fun expr -> package, expr))
            |> Memo.List.map ~f:(fun (package, expr) ->
              Blang_expand.eval
                expr
                ~dir:Path.root (* This value is irrelevant *)
                ~f:(fun ~source:_ pform ->
                  match pform with
                  | Var (Os v) -> Lock_dir.Sys_vars.(os_values poll v)
                  | Var Architecture ->
                    let+ arch = Memo.Lazy.force Lock_dir.Sys_vars.poll.arch in
                    [ Value.String (Option.value ~default:"" arch) ]
                  | _ -> assert false)
              >>| function
              | true -> None
              | false -> Some package)
            >>| List.filter_opt
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
  let (_ : Package.Name.t Path.Source.Map.t) =
    match
      Package.Name.Map.values all_packages
      |> List.filter_map ~f:(fun (pkg, _) ->
        match Package.exclusive_dir pkg with
        | None -> None
        | Some d -> Some (d, pkg))
      |> Path.Source.Map.of_list_map ~f:(fun ((_loc, d), pkg) -> d, Package.name pkg)
    with
    | Ok s -> s
    | Error (dir, ((loc, _), p1), (_, p2)) ->
      let name p = Package.Name.to_string (Package.name p) in
      User_error.raise
        ~loc
        [ Pp.textf
            "Directory %s cannot belong to package %s"
            (Path.Source.to_string_maybe_quoted dir)
            (name p1)
        ; Pp.textf "It already belongs to package %s" (name p2)
        ]
  in
  let* dune_files_by_ctx = Dune_file.eval dune_files mask in
  let+ dune_files = dune_files_by_ctx ctx in
  let projects_by_root =
    Path.Source.Map.of_list_map_exn projects ~f:(fun project ->
      Dune_project.root project, project)
  in
  let dune_file_by_dir = Dune_file_db.make dune_files in
  { Ctx_data.dune_files; mask; dune_file_by_dir; packages; projects; projects_by_root }
;;

let load () =
  let ctx_data =
    Staged.unstage
      (Per_context.create_by_name ~name:"dune-load-ctx-data" (fun ctx ->
         Memo.lazy_ (fun () -> load_for_context_impl ctx) |> Memo.Lazy.force))
  in
  Memo.return { ctx_data }
;;

let load =
  let memo = Memo.lazy_ ~name:"dune_load" load in
  fun () -> Memo.Lazy.force memo
;;

let ctx_data context =
  let* t = load () in
  t.ctx_data context
;;

let find_project ~dir =
  match Install.Context.of_path dir with
  | None ->
    Code_error.raise
      "Dune_load.find_project: dir is not under a build context"
      [ "dir", Path.Build.to_dyn dir ]
  | Some context ->
    let+ { Ctx_data.projects_by_root; _ } = ctx_data context in
    Find_closest_source_dir.find_by_dir_exn projects_by_root ~dir
;;

let stanzas_in_dir dir =
  if Path.Build.is_root dir
  then Memo.return None
  else (
    match Install.Context.of_path dir with
    | None -> Memo.return None
    | Some ctx ->
      let src_dir = Path.Build.drop_build_context_exn dir in
      let+ { Ctx_data.dune_file_by_dir; _ } = ctx_data ctx in
      Path.Source.Map.find dune_file_by_dir src_dir)
;;

let mask context =
  let+ { Ctx_data.mask; _ } = ctx_data context in
  mask
;;

let packages context =
  let+ { Ctx_data.packages; _ } = ctx_data context in
  packages
;;

let dune_files context =
  let+ { Ctx_data.dune_files; _ } = ctx_data context in
  dune_files
;;

let projects_by_root context =
  let+ { Ctx_data.projects_by_root; _ } = ctx_data context in
  projects_by_root
;;

let projects context =
  let+ { Ctx_data.projects; _ } = ctx_data context in
  projects
;;

let workspace_packages () =
  let* contexts = Per_context.list () in
  let+ pkgs_per_ctx = Memo.parallel_map contexts ~f:packages in
  List.fold_left pkgs_per_ctx ~init:Package.Name.Map.empty ~f:(fun acc pkgs ->
    Package.Name.Map.union acc pkgs ~f:(fun _ a _ -> Some a))
;;

let workspace_projects () =
  let* contexts = Per_context.list () in
  let+ projects_per_ctx = Memo.parallel_map contexts ~f:projects in
  List.concat projects_per_ctx
  |> List.fold_left ~init:Path.Source.Map.empty ~f:(fun acc p ->
    Path.Source.Map.set acc (Dune_project.root p) p)
  |> Path.Source.Map.values
;;
