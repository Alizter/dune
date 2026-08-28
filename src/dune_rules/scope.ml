open Import
open Memo.O

type t =
  { project : Dune_project.t
  ; source_root : Source_path.t
  ; db : Lib.DB.t
  ; public_libs : Lib.DB.t
  ; rocq_db : Rocq_lib.DB.t Memo.t
  ; root : Path.Build.t
  ; purpose : Build_partition.purpose
  }

let root t = t.root
let project t = t.project
let libs t = t.db

let source_dir t dir =
  let relative = Path.drop_prefix_exn (Path.build dir) ~prefix:(Path.build t.root) in
  Source_path.append_local t.source_root relative
;;

let rocq_libs t = t.rocq_db

module DB = struct
  type scope = t

  type t =
    { by_dir : scope Path.Build.Map.t
    ; by_project : scope list
    }

  let find_scope_by_dir t dir =
    let rec loop dir =
      match Path.Build.Map.find t.by_dir dir with
      | Some scope -> scope
      | None ->
        (match Path.Build.parent dir with
         | Some parent -> loop parent
         | None ->
           Code_error.raise
             "Scope.DB.find_by_dir: no enclosing scope"
             [ "dir", Path.Build.to_dyn dir ])
    in
    loop dir
  ;;

  let find_scope_by_project t project =
    List.find_exn t.by_project ~f:(fun scope -> Dune_project.equal project scope.project)
  ;;

  module Found_or_redirect : sig
    type t = private
      | Found of Lib_info.external_
      | Redirect of
          { loc : Loc.t
          ; to_ : Lib_name.t
          ; enabled : Toggle.t Memo.t
          }
      | Deprecated_library_name of (Loc.t * Lib_name.t)

    val redirect
      :  enabled:Toggle.t Memo.t
      -> Lib_name.t
      -> Loc.t * Lib_name.t
      -> Lib_name.t * t

    val deprecated_library_name : Lib_name.t -> Loc.t * Lib_name.t -> Lib_name.t * t
    val found : Lib_info.external_ -> t
  end = struct
    type t =
      | Found of Lib_info.external_
      | Redirect of
          { loc : Loc.t
          ; to_ : Lib_name.t
          ; enabled : Toggle.t Memo.t
          }
      | Deprecated_library_name of (Loc.t * Lib_name.t)

    let redirect ~enabled from (loc, to_) =
      if Lib_name.equal from to_
      then Code_error.raise ~loc "Invalid redirect" [ "to_", Lib_name.to_dyn to_ ]
      else from, Redirect { loc; to_; enabled }
    ;;

    let deprecated_library_name from (loc, to_) =
      if Lib_name.equal from to_
      then Code_error.raise ~loc "Invalid redirect" [ "to_", Lib_name.to_dyn to_ ]
      else from, Deprecated_library_name (loc, to_)
    ;;

    let found x = Found x
  end

  module Library_related_stanza = struct
    type t =
      | Library of Library.t
      | Library_redirect of Library_redirect.Local.t
      | Deprecated_library_name of Deprecated_library_name.t
  end

  let create_db_from_stanzas =
    (* Here, [parent] is always the public_libs DB. Check the call to
       [create_db_from_stanzas] below. *)
    let resolve_found_or_redirect ~public_libs fr =
      match (fr : Found_or_redirect.t) with
      | Redirect { loc; to_; enabled; _ } ->
        let+ enabled =
          let+ toggle = enabled in
          Toggle.enabled toggle
        in
        if enabled
        then Lib.DB.Resolve_result.redirect_in_the_same_db (loc, to_)
        else Lib.DB.Resolve_result.not_found
      | Found lib -> Memo.return (Lib.DB.Resolve_result.found lib)
      | Deprecated_library_name lib ->
        Memo.return (Lib.DB.Resolve_result.redirect_by_name public_libs lib)
    in
    let resolve_lib_id ~public_libs lib_id_map lib_id =
      match Lib_id.Map.find lib_id_map lib_id with
      | None -> Memo.return Lib.DB.Resolve_result.not_found
      | Some found_or_redirect -> resolve_found_or_redirect ~public_libs found_or_redirect
    in
    fun ~instrument_with ~public_libs ~lib_config stanzas ->
      let by_name, by_id, _ =
        List.fold_left
          stanzas
          ~init:(Lib_name.Map.empty, Lib_id.Map.empty, Lib_name.Map.empty)
          ~f:(fun (by_name, by_id, libname_conflict_map) (dir, src_dir, stanza) ->
            let lib_id, name, r2 =
              match (stanza : Library_related_stanza.t) with
              | Library_redirect s ->
                let lib_name, redirect =
                  let old_public_name = Lib_name.of_local s.old_name.lib_name in
                  let enabled =
                    Memo.lazy_ ~name:"library-redirect-enabled" (fun () ->
                      let* expander = Expander0.get ~dir in
                      Expander0.eval_blang expander s.old_name.enabled >>| Toggle.of_bool)
                    |> Memo.Lazy.force
                  in
                  Found_or_redirect.redirect ~enabled old_public_name s.new_public_name
                and lib_id = Library_redirect.Local.to_lib_id ~src_dir s in
                Some lib_id, lib_name, redirect
              | Deprecated_library_name s ->
                let lib_name, deprecated_lib =
                  let old_public_name = Deprecated_library_name.old_public_name s in
                  Found_or_redirect.deprecated_library_name
                    old_public_name
                    s.new_public_name
                in
                None, lib_name, deprecated_lib
              | Library (conf : Library.t) ->
                let info =
                  let expander = Expander0.get ~dir in
                  Library.to_lib_info conf ~expander ~dir ~src_dir ~lib_config
                  |> Lib_info.of_local
                and lib_id = Library.to_lib_id ~src_dir conf in
                Some lib_id, Library.best_name conf, Found_or_redirect.found info
            in
            let libname_conflict_map =
              Lib_name.Map.update libname_conflict_map name ~f:(function
                | None -> Some r2
                | Some (r1 : Found_or_redirect.t) ->
                  let res =
                    match r1, r2 with
                    | Found _, Found _
                    | Found _, Redirect _
                    | Redirect _, Found _
                    | Redirect _, Redirect _ -> Ok r1
                    | Found info, Deprecated_library_name (loc, _)
                    | Deprecated_library_name (loc, _), Found info ->
                      Error (loc, Lib_info.loc info)
                    | ( Deprecated_library_name (loc2, lib2)
                      , Redirect { loc = loc1; to_ = lib1; _ } )
                    | ( Redirect { loc = loc1; to_ = lib1; _ }
                      , Deprecated_library_name (loc2, lib2) )
                    | ( Deprecated_library_name (loc1, lib1)
                      , Deprecated_library_name (loc2, lib2) ) ->
                      if Lib_name.equal lib1 lib2 then Ok r1 else Error (loc1, loc2)
                  in
                  (match res with
                   | Ok x -> Some x
                   | Error (loc1, loc2) ->
                     let main_message =
                       Pp.textf "Library %s is defined twice:" (Lib_name.to_string name)
                     in
                     let compound =
                       Compound_user_error.duplicate
                         ~main_loc:loc2
                         ~previous_loc:loc1
                         main_message
                     in
                     User_error.raise
                       ~compound
                       [ main_message
                       ; Pp.textf "- %s" (Loc.to_file_colon_line loc1)
                       ; Pp.textf "- %s" (Loc.to_file_colon_line loc2)
                       ]))
            in
            let by_name =
              Lib_name.Map.update by_name name ~f:(function
                | None -> Some [ r2 ]
                | Some rest -> Some (r2 :: rest))
            and by_id =
              match lib_id with
              | None -> by_id
              | Some lib_id -> Lib_id.Map.add_exn by_id (Local lib_id) r2
            in
            by_name, by_id, libname_conflict_map)
      in
      let resolve name =
        match Lib_name.Map.find by_name name with
        | None | Some [] -> Memo.return []
        | Some [ fr ] -> resolve_found_or_redirect ~public_libs fr >>| List.singleton
        | Some frs -> Memo.parallel_map frs ~f:(resolve_found_or_redirect ~public_libs)
      and resolve_lib_id = resolve_lib_id ~public_libs by_id in
      Lib.DB.create
        ()
        ~parent:(Some public_libs)
        ~resolve
        ~resolve_lib_id
        ~all:(fun () -> Lib_name.Map.keys by_name |> Memo.return)
        ~instrument_with
  ;;

  let dynamic_libraries context libraries ~parent =
    let db_ref = Fdecl.create Dyn.opaque in
    let find =
      let memo =
        Memo.create
          "dynamic-library-db"
          ~input:(module Lib_name)
          (fun name ->
             let* libraries = libraries in
             let package = Lib_name.package_name name in
             let db_if_available paths =
               let* db = Lib.DB.of_paths context ~paths in
               let+ available = Lib.DB.available db name in
               if available
               then Some (Lib.DB.with_parent db ~parent:(Fdecl.get db_ref))
               else None
             in
             let find_provider () =
               let* available_from_parent = Lib.DB.available parent name in
               if available_from_parent
               then Memo.return None
               else
                 let* paths =
                   Pkg_rules.Legacy_libraries.find_provider libraries package
                 in
                 Memo.Option.bind paths ~f:db_if_available
             in
             Pkg_rules.Legacy_libraries.find libraries package
             >>= function
             | None -> find_provider ()
             | Some paths ->
               db_if_available paths
               >>= (function
                | Some _ as db -> Memo.return db
                | None -> find_provider ()))
      in
      Memo.exec memo
    in
    let resolve name =
      let+ db = find name in
      match db with
      | None -> Lib.DB.Resolve_result.not_found
      | Some db -> Lib.DB.Resolve_result.redirect_by_name db (Loc.none, name)
    in
    let db =
      Lib.DB.create
        ~parent:(Some parent)
        ~resolve:(fun name ->
          let+ resolved = resolve name in
          [ resolved ])
        ~resolve_lib_id:(fun lib_id -> resolve (Lib_id.name lib_id))
        ~all:(fun () ->
          let+ libraries = libraries in
          Pkg_rules.Legacy_libraries.packages libraries
          |> List.map ~f:Lib_name.of_package_name)
        ~instrument_with:(Context.instrument_with context)
        ()
    in
    Fdecl.set db_ref db;
    db
  ;;

  let legacy_libraries context package ~parent =
    dynamic_libraries
      context
      (Pkg_rules.Legacy_libraries.for_package (Context.name context) package)
      ~parent
  ;;

  type redirect_to =
    | Project of
        { project : Dune_project.t
        ; lib_id : Lib_id.Local.t
        ; enabled : Toggle.t Memo.t
        ; loc : Loc.t
        }
    | Name of (Loc.t * Lib_name.t)

  (* Create a database from the public libraries defined in the stanzas *)
  let public_libs =
    let resolve_redirect_to t rt =
      match rt with
      | Project { project; lib_id; enabled; _ } ->
        let+ enabled =
          let+ toggle = enabled in
          Toggle.enabled toggle
        in
        if enabled
        then (
          let scope = find_scope_by_project (Fdecl.get t) project in
          Lib.DB.Resolve_result.redirect_by_id scope.db (Local lib_id))
        else Lib.DB.Resolve_result.not_found
      | Name name -> Memo.return (Lib.DB.Resolve_result.redirect_in_the_same_db name)
    in
    let resolve_lib_id t public_libs mounted_public_libs lib_id =
      match Lib_id.Map.find public_libs lib_id with
      | Some rt -> resolve_redirect_to t rt
      | None ->
        (match lib_id with
         | Local _ -> Memo.return Lib.DB.Resolve_result.not_found
         | External (_, name) ->
           (match Lib_name.Map.find mounted_public_libs name with
            | Some [ rt ] -> resolve_redirect_to t rt
            | None | Some [] | Some (_ :: _ :: _) ->
              Memo.return Lib.DB.Resolve_result.not_found))
    in
    fun t ~installed_libs ~instrument_with stanzas ->
      let by_name, by_id, mounted_by_name =
        List.fold_left
          stanzas
          ~init:(Lib_name.Map.empty, Lib_id.Map.empty, Lib_name.Map.empty)
          ~f:
            (fun
              (by_name, by_id, mounted_by_name)
              ((loaded_project, dir, src_dir, stanza) :
                Loaded_project.t * Path.Build.t * Source_path.t * Library_related_stanza.t)
            ->
            let candidate =
              match stanza with
              | Library ({ project; visibility = Public p; _ } as conf) ->
                let lib_id = Library.to_lib_id ~src_dir conf in
                let enabled =
                  Memo.lazy_ ~name:"library-enabled" (fun () ->
                    let* expander = Expander0.get ~dir in
                    Expander0.eval_blang expander conf.enabled_if >>| Toggle.of_bool)
                  |> Memo.Lazy.force
                in
                Some
                  ( Public_lib.name p
                  , Project { project; lib_id; enabled; loc = Public_lib.loc p }
                  , Some lib_id )
              | Library _ | Library_redirect _ -> None
              | Deprecated_library_name s ->
                Some
                  (Deprecated_library_name.old_public_name s, Name s.new_public_name, None)
            in
            match candidate with
            | None -> by_name, by_id, mounted_by_name
            | Some (public_name, r2, lib_id2) ->
              let by_name =
                Lib_name.Map.update by_name public_name ~f:(function
                  | None -> Some [ r2 ]
                  | Some r1 -> Some (r2 :: r1))
              in
              let by_id =
                match lib_id2 with
                | None -> by_id
                | Some lib_id2 -> Lib_id.Map.add_exn by_id (Local lib_id2) r2
              in
              let mounted_by_name =
                match
                  ( Loaded_project.partition loaded_project |> Build_partition.purpose
                  , lib_id2 )
                with
                | Mounted, Some _ ->
                  Lib_name.Map.update mounted_by_name public_name ~f:(function
                    | None -> Some [ r2 ]
                    | Some rest -> Some (r2 :: rest))
                | Workspace, _ | Mounted, None -> mounted_by_name
              in
              by_name, by_id, mounted_by_name)
      in
      let resolve_mounted name =
        match Lib_name.Map.find mounted_by_name name with
        | Some [ rt ] -> resolve_redirect_to t rt
        | None | Some [] | Some (_ :: _ :: _) ->
          Memo.return Lib.DB.Resolve_result.not_found
      in
      let mounted_libs =
        Lib.DB.create
          ~parent:None
          ~resolve:(fun name ->
            let+ resolved = resolve_mounted name in
            [ resolved ])
          ~resolve_lib_id:(function
            | External (_, name) -> resolve_mounted name
            | Local _ -> Memo.return Lib.DB.Resolve_result.not_found)
          ~all:(fun () -> Lib_name.Map.keys mounted_by_name |> Memo.return)
          ~instrument_with
          ()
      in
      let installed_libs =
        if Lib_name.Map.is_empty mounted_by_name
        then installed_libs
        else Lib.DB.with_parent installed_libs ~parent:mounted_libs
      in
      let resolve_lib_id lib_id = resolve_lib_id t by_id mounted_by_name lib_id in
      let resolve name =
        match Lib_name.Map.find by_name name with
        | None -> Memo.return []
        | Some rt -> Memo.List.map ~f:(resolve_redirect_to t) rt
      in
      Lib.DB.create
        ~parent:(Some installed_libs)
        ~resolve
        ~resolve_lib_id
        ~all:(fun () -> Lib_name.Map.keys by_name |> Memo.return)
        ~instrument_with
        ()
  ;;

  let scopes_by_dir
        ~lib_config
        ~loaded_projects
        ~public_libs
        ~installed_libs
        ~instrument_with
        context
        stanzas
        rocq_stanzas
    =
    let stanzas_by_project =
      List.map stanzas ~f:(fun (loaded_project, dir, source_dir, stanza) ->
        Loaded_project.output_root loaded_project, (dir, source_dir, stanza))
      |> Path.Build.Map.of_list_multi
    in
    let projects_by_output_root =
      Path.Build.Map.of_list_map_exn loaded_projects ~f:(fun loaded_project ->
        Loaded_project.output_root loaded_project, loaded_project)
    in
    let db_by_project =
      Path.Build.Map.merge
        projects_by_output_root
        stanzas_by_project
        ~f:(fun _dir loaded_project stanzas ->
          let loaded_project = Option.value_exn loaded_project in
          let project = Loaded_project.project loaded_project in
          let stanzas = Option.value stanzas ~default:[] in
          Some (loaded_project, project, stanzas))
      |> Path.Build.Map.map ~f:(fun (loaded_project, project, stanzas) ->
        let public_libs =
          match Build_partition.purpose (Loaded_project.partition loaded_project) with
          | Workspace -> public_libs
          | Mounted ->
            let package =
              match Loaded_project.visible_packages loaded_project with
              | Some packages ->
                (match Package.Name.Set.to_list packages with
                 | [ package ] -> package
                 | _ ->
                   Code_error.raise
                     "Mounted project does not have exactly one visible package"
                     [ "project", Loaded_project.to_dyn loaded_project ])
              | None ->
                Code_error.raise
                  "Mounted project has no visible package"
                  [ "project", Loaded_project.to_dyn loaded_project ]
            in
            let legacy_libs = legacy_libraries context package ~parent:installed_libs in
            Lib.DB.with_parent public_libs ~parent:legacy_libs
        in
        let db =
          create_db_from_stanzas stanzas ~instrument_with ~public_libs ~lib_config
        in
        loaded_project, project, db, public_libs)
    in
    let db_by_project_output_root =
      Path.Build.Map.map db_by_project ~f:(fun (loaded_project, _, db, _) ->
        loaded_project, db)
    in
    let rocq_scopes =
      Rocq_scope.make context ~public_libs ~db_by_project_output_root rocq_stanzas
    in
    Path.Build.Map.map db_by_project ~f:(fun (loaded_project, project, db, public_libs) ->
      let root = Loaded_project.output_root loaded_project in
      let source_root = Loaded_project.source_root loaded_project in
      let rocq_db = Rocq_scope.find rocq_scopes ~project:loaded_project in
      let purpose = Loaded_project.partition loaded_project |> Build_partition.purpose in
      { project; source_root; db; public_libs; rocq_db; root; purpose })
  ;;

  let create ~installed_libs ~context ~loaded_projects stanzas rocq_stanzas =
    let t = Fdecl.create Dyn.opaque in
    let* context = Context.DB.get context
    and* opam_package_names = Opam_rules.package_names context in
    let* lib_config =
      let+ ocaml = Context.ocaml context in
      ocaml.lib_config
    in
    let instrument_with = Context.instrument_with context in
    let with_opam_libraries packages ~parent =
      let packages = List.filter packages ~f:(Package.Name.Set.mem opam_package_names) in
      match packages with
      | [] -> parent
      | _ :: _ -> Opam_rules.libraries context packages ~parent
    in
    let public_libs = public_libs t ~instrument_with ~installed_libs stanzas in
    let scopes =
      scopes_by_dir
        ~lib_config
        ~loaded_projects
        ~public_libs
        ~installed_libs
        ~instrument_with
        context
        stanzas
        rocq_stanzas
    in
    let by_project = Path.Build.Map.values scopes in
    let by_dir =
      Path.Build.Map.fold scopes ~init:scopes ~f:(fun scope by_dir ->
        match scope.purpose with
        | Mounted -> by_dir
        | Workspace ->
          let packages = Dune_project.packages scope.project in
          Package.Name.Map.fold packages ~init:by_dir ~f:(fun package by_dir ->
            match Package.exclusive_dir package with
            | None -> by_dir
            | Some (_, package_dir) ->
              let package_output_dir =
                let local =
                  Source_path.descendant package_dir ~of_:scope.source_root
                  |> Option.value_exn
                in
                Path.Build.append_local scope.root local
              in
              let rec add_dependencies name visited =
                if Package.Name.Set.mem visited name
                then visited
                else (
                  let visited = Package.Name.Set.add visited name in
                  match Package.Name.Map.find packages name with
                  | None -> visited
                  | Some package ->
                    List.fold_left
                      (Package.depends package)
                      ~init:visited
                      ~f:(fun visited dependency ->
                        add_dependencies dependency.Package_dependency.name visited))
              in
              let dependencies =
                List.fold_left
                  (Package.depends package)
                  ~init:Package.Name.Set.empty
                  ~f:(fun visited dependency ->
                    add_dependencies dependency.Package_dependency.name visited)
                |> Package.Name.Set.to_list
              in
              let public_libs =
                with_opam_libraries dependencies ~parent:scope.public_libs
              in
              let scope =
                { scope with
                  db = Lib.DB.with_parent scope.db ~parent:public_libs
                ; public_libs
                }
              in
              Path.Build.Map.set by_dir package_output_dir scope))
    in
    let by_dir =
      Path.Build.Map.fold scopes ~init:by_dir ~f:(fun scope by_dir ->
        match scope.purpose with
        | Mounted -> by_dir
        | Workspace ->
          let packages = Dune_project.packages scope.project |> Package.Name.Map.keys in
          let public_libs = with_opam_libraries packages ~parent:scope.public_libs in
          let scope =
            { scope with
              db = Lib.DB.with_parent scope.db ~parent:public_libs
            ; public_libs
            }
          in
          Path.Build.Map.set by_dir scope.root scope)
    in
    let value = { by_dir; by_project } in
    Fdecl.set t value;
    let public_libs =
      List.concat_map loaded_projects ~f:(fun loaded_project ->
        match Loaded_project.partition loaded_project |> Build_partition.purpose with
        | Mounted -> []
        | Workspace ->
          Loaded_project.project loaded_project
          |> Dune_project.packages
          |> Package.Name.Map.keys)
      |> List.sort_uniq ~compare:Package.Name.compare
      |> with_opam_libraries ~parent:public_libs
    in
    Memo.return (value, public_libs)
  ;;

  let create_from_stanzas_internal
        ~installed_libs
        ~loaded_projects
        ~(context : Context_name.t)
        stanzas
    =
    let stanzas, rocq_stanzas =
      Dune_file.fold_static_stanzas
        stanzas
        ~init:([], [])
        ~f:(fun dune_file stanza (acc, rocq_acc) ->
          let loaded_project = Dune_file.loaded_dir dune_file |> Loaded_dir.project in
          let output_dir = Dune_file.output_dir dune_file in
          let source_dir = Dune_file.source_dir dune_file in
          match Stanza.repr stanza with
          | Library.T lib ->
            ( (loaded_project, output_dir, source_dir, Library_related_stanza.Library lib)
              :: acc
            , rocq_acc )
          | Deprecated_library_name.T d ->
            ( (loaded_project, output_dir, source_dir, Deprecated_library_name d) :: acc
            , rocq_acc )
          | Library_redirect.Local.T d ->
            (loaded_project, output_dir, source_dir, Library_redirect d) :: acc, rocq_acc
          | Rocq_stanza.Theory.T rocq_lib ->
            acc, (loaded_project, output_dir, rocq_lib) :: rocq_acc
          | _ -> acc, rocq_acc)
    in
    create ~installed_libs ~loaded_projects ~context stanzas rocq_stanzas
  ;;

  let make_all ~name ~mounted =
    Per_context.create_by_name ~name (fun context ->
      Memo.Lazy.create ~name (fun () ->
        let* loaded_projects = Dune_load.loaded_projects context
        and* stanzas = Dune_load.dune_files context
        and* context_value = Context.DB.get context in
        let* installed_libs =
          if mounted
          then
            let* paths = Context.default_ocamlpath context_value in
            Lib.DB.of_paths context_value ~paths
          else Lib.DB.installed context_value
        in
        create_from_stanzas_internal ~installed_libs ~loaded_projects ~context stanzas)
      |> Memo.Lazy.force)
    |> Staged.unstage
  ;;

  let workspace_scopes = make_all ~name:"scope" ~mounted:false
  let mounted_scopes = make_all ~name:"mounted-scope" ~mounted:true

  let scopes_for_purpose purpose =
    match (purpose : Build_partition.purpose) with
    | Workspace -> workspace_scopes
    | Mounted -> mounted_scopes
  ;;

  let create_from_stanzas (context : Context_name.t) = workspace_scopes context

  let with_all context ~f =
    let+ scopes, _ = create_from_stanzas (Context.name context) in
    let find = find_scope_by_project scopes in
    f find
  ;;

  let public_libs context =
    let+ _, public_libs = create_from_stanzas context in
    public_libs
  ;;

  let public_libs_by_dir dir =
    let* context = Context.DB.by_dir dir
    and* loaded_project = Dune_load.find_loaded_project ~dir in
    let purpose = Loaded_project.partition loaded_project |> Build_partition.purpose in
    let+ scopes, _ = scopes_for_purpose purpose (Context.name context) in
    (find_scope_by_dir scopes dir).public_libs
  ;;

  let find_by_dir dir =
    let* context = Context.DB.by_dir dir
    and* loaded_project = Dune_load.find_loaded_project ~dir in
    let purpose = Loaded_project.partition loaded_project |> Build_partition.purpose in
    let+ scopes, _ = scopes_for_purpose purpose (Context.name context) in
    find_scope_by_dir scopes dir
  ;;

  let find_by_project context project =
    let* loaded_projects = Dune_load.loaded_projects context in
    let loaded_project =
      List.find_exn loaded_projects ~f:(fun loaded_project ->
        Dune_project.equal project (Loaded_project.project loaded_project))
    in
    let purpose = Loaded_project.partition loaded_project |> Build_partition.purpose in
    let+ scopes, _ = scopes_for_purpose purpose context in
    find_scope_by_project scopes project
  ;;

  module Lib_entry = struct
    type t =
      | Library of Lib.Local.t
      | Deprecated_library_name of Deprecated_library_name.t

    let name = function
      | Library lib -> Lib.Local.to_lib lib |> Lib.name
      | Deprecated_library_name { old_name = old_public_name, _; _ } ->
        Public_lib.name old_public_name
    ;;

    let loc = function
      | Library lib -> Lib.Local.to_lib lib |> Lib.info |> Lib_info.loc
      | Deprecated_library_name { old_name = old_public_name, _; _ } ->
        Public_lib.loc old_public_name
    ;;

    module Set = struct
      type t =
        { libraries : Lib.Local.t list
        ; deprecated_library_names : Deprecated_library_name.t list
        }

      let empty = { libraries = []; deprecated_library_names = [] }

      let of_list =
        let by_name x = Lib.Local.info x |> Lib_info.name in
        fun xs ->
          let libraries, deprecated_library_names =
            List.partition_map xs ~f:(function
              | Library l -> Left l
              | Deprecated_library_name l -> Right l)
          in
          { libraries =
              List.sort libraries ~compare:(fun x y ->
                Lib_name.compare (by_name x) (by_name y))
          ; deprecated_library_names =
              List.sort
                deprecated_library_names
                ~compare:(fun { old_name = old_public_name, _; _ } y ->
                  Lib_name.compare
                    (Public_lib.name old_public_name)
                    (Public_lib.name (fst y.old_name)))
          }
      ;;

      let fold { libraries; deprecated_library_names } ~init ~f =
        let init =
          List.fold_left ~init libraries ~f:(fun acc lib -> f (Library lib) acc)
        in
        List.fold_left deprecated_library_names ~init ~f:(fun acc dep ->
          f (Deprecated_library_name dep) acc)
      ;;

      let partition_map t ~f =
        let l, r =
          fold t ~init:([], []) ~f:(fun x (l, r) ->
            match f x with
            | Left x -> x :: l, r
            | Right x -> l, x :: r)
        in
        List.(rev l, rev r)
      ;;
    end
  end

  let check_duplicate_lib_entries libs =
    let _by_name =
      Lib_entry.Set.fold libs ~init:Lib_name.Map.empty ~f:(fun entry2 by_name ->
        let public_name = Lib_entry.name entry2 in
        Lib_name.Map.update by_name public_name ~f:(function
          | None -> Some entry2
          | Some entry1 ->
            let loc1 = Lib_entry.loc entry1
            and loc2 = Lib_entry.loc entry2 in
            let main_message =
              Pp.textf
                "Public library %s is defined twice:"
                (Lib_name.to_string public_name)
            in
            let compound =
              Compound_user_error.duplicate ~main_loc:loc2 ~previous_loc:loc1 main_message
            in
            User_error.raise
              ~compound
              ~loc:loc2
              [ main_message
              ; Pp.textf "- %s" (Loc.to_file_colon_line loc1)
              ; Pp.textf "- %s" (Loc.to_file_colon_line loc2)
              ]))
    in
    libs
  ;;

  let lib_entries_of_package =
    let make_map public_libs stanzas =
      let+ libs =
        Dune_file.Memo_fold.fold_static_stanzas stanzas ~init:[] ~f:(fun d stanza acc ->
          match Stanza.repr stanza with
          | Library.T ({ enabled_if; _ } as lib) ->
            let src_dir = Dune_file.source_dir d in
            let lib_dir = Dune_file.output_dir d in
            let* package_and_db =
              match lib.visibility with
              | Private None -> Memo.return None
              | Private (Some package) ->
                let+ scope = find_by_dir lib_dir in
                Some (package, libs scope)
              | Public public ->
                Memo.return (Some (Public_lib.package public, public_libs))
            in
            (match package_and_db with
             | None -> Memo.return acc
             | Some (package, db) ->
               let* enabled =
                 let* expander = Expander0.get ~dir:lib_dir in
                 Expander0.eval_blang expander enabled_if
               in
               if not enabled
               then Memo.return acc
               else
                 Lib.DB.find_lib_id db (Local (Library.to_lib_id ~src_dir lib))
                 >>| (function
                  | None -> acc
                  | Some lib ->
                    (Package.name package, Lib_entry.Library (Lib.Local.of_lib_exn lib))
                    :: acc))
          | Deprecated_library_name.T ({ old_name = old_public_name, _; _ } as d) ->
            let package = Public_lib.package old_public_name in
            let name = Package.name package in
            Memo.return ((name, Lib_entry.Deprecated_library_name d) :: acc)
          | _ -> Memo.return acc)
      in
      Package.Name.Map.of_list_multi libs |> Package.Name.Map.map ~f:Lib_entry.Set.of_list
    in
    let per_context =
      Per_context.create_by_name ~name:"scope-db" (fun ctx ->
        Memo.lazy_ ~name:"scope-db" (fun () ->
          let* public_libs =
            let* ctx = Context.DB.get ctx in
            public_libs (Context.name ctx)
          and* stanzas = Dune_load.dune_files ctx in
          make_map public_libs stanzas)
        |> Memo.Lazy.force)
      |> Staged.unstage
    in
    fun (ctx : Context_name.t) pkg_name ->
      let+ map = per_context ctx in
      match Package.Name.Map.find map pkg_name with
      | None -> Lib_entry.Set.empty
      | Some libs -> check_duplicate_lib_entries libs
  ;;

  let lib_entries_of_loaded_project ctx loaded_project pkg_name =
    let loaded_project_identity = Loaded_project.identity loaded_project in
    let* stanzas = Dune_load.dune_files ctx
    and* loaded_projects = Dune_load.loaded_projects ctx
    and* context = Context.DB.get ctx in
    let* installed_libs =
      let* paths = Context.default_ocamlpath context in
      Lib.DB.of_paths context ~paths
    in
    let* scopes, _ =
      create_from_stanzas_internal ~installed_libs ~loaded_projects ~context:ctx stanzas
    in
    let+ entries =
      Dune_file.Memo_fold.fold_static_stanzas stanzas ~init:[] ~f:(fun d stanza acc ->
        let stanza_project = Dune_file.loaded_dir d |> Loaded_dir.project in
        if
          not
            (Loaded_project.Identity.equal
               loaded_project_identity
               (Loaded_project.identity stanza_project))
        then Memo.return acc
        else (
          match Stanza.repr stanza with
          | Library.T ({ enabled_if; _ } as lib) ->
            let package =
              match lib.visibility with
              | Private package -> Option.map package ~f:Package.name
              | Public public -> Some (Public_lib.package public |> Package.name)
            in
            if not (Option.equal Package.Name.equal package (Some pkg_name))
            then Memo.return acc
            else (
              let src_dir = Dune_file.source_dir d in
              let lib_dir = Dune_file.output_dir d in
              let* enabled =
                let* expander = Expander0.get ~dir:lib_dir in
                Expander0.eval_blang expander enabled_if
              in
              if not enabled
              then Memo.return acc
              else (
                let scope = find_scope_by_dir scopes lib_dir in
                Lib.DB.find_lib_id (libs scope) (Local (Library.to_lib_id ~src_dir lib))
                >>| function
                | None -> acc
                | Some lib -> Lib_entry.Library (Lib.Local.of_lib_exn lib) :: acc))
          | Deprecated_library_name.T ({ old_name = old_public_name, _; _ } as deprecated)
            ->
            let package = Public_lib.package old_public_name |> Package.name in
            if Package.Name.equal package pkg_name
            then Memo.return (Lib_entry.Deprecated_library_name deprecated :: acc)
            else Memo.return acc
          | _ -> Memo.return acc))
    in
    ( Lib_entry.Set.of_list entries |> check_duplicate_lib_entries
    , find_scope_by_dir scopes (Loaded_project.output_root loaded_project) )
  ;;
end
