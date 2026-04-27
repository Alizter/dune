open Import
open Action_builder.O

let make_sandboxing_config config =
  let loc = Dep_conf.Sandbox_config.loc config in
  Dep_conf.Sandbox_config.fold config ~init:[] ~f:(fun kind acc ->
    let partial =
      match kind with
      | `None -> Sandbox_config.Partial.no_sandboxing
      | `Always -> Sandbox_config.Partial.needs_sandboxing
      | `Preserve_file_kind -> Sandbox_config.Partial.disallow Sandbox_mode.symlink
      | `Patch_back_source_tree -> Sandbox_config.Partial.patch_back_source_tree
    in
    partial :: acc)
  |> Dune_engine.Sandbox_config.Partial.merge ~loc
;;

let make_alias expander s =
  let loc = String_with_vars.loc s in
  Expander.expand_path expander s >>| Alias.of_user_written_path ~loc
;;

let package_install ~(context : Build_context.t) ~(pkg : Package.t) =
  let dir =
    let dir = Package.dir pkg in
    Path.Build.append_source context.build_dir dir
  in
  let name = Package.name pkg in
  sprintf ".%s-files" (Package.Name.to_string name)
  |> Alias.Name.of_string
  |> Alias.make ~dir
;;

type dep_evaluation_result =
  | Simple of Path.t list Memo.t
  | Other of Path.t list Action_builder.t

let to_action_builder = function
  | Simple paths ->
    let* paths = Action_builder.of_memo paths in
    let+ () = Action_builder.all_unit (List.map ~f:Action_builder.path paths) in
    paths
  | Other x -> x
;;

let dep_on_alias_rec alias ~loc =
  let src_dir = Path.Build.drop_build_context_exn (Alias.dir alias) in
  Action_builder.of_memo (Source_tree.find_dir src_dir)
  >>= function
  | None ->
    Action_builder.fail
      { fail =
          (fun () ->
            User_error.raise
              ~loc
              [ Pp.textf
                  "Don't know about directory %s!"
                  (Path.Source.to_string_maybe_quoted src_dir)
              ])
      }
  | Some _ ->
    let name = Dune_engine.Alias.name alias in
    Alias_rec.dep_on_alias_rec name (Alias.dir alias)
    >>| (function
     | Defined -> ()
     | Not_defined ->
       if not (Alias0.is_standard name)
       then
         User_error.raise
           ~loc
           [ Pp.text "This alias is empty."
           ; Pp.textf
               "Alias %S is not defined in %s or any of its descendants."
               (Alias.Name.to_string name)
               (Path.Source.to_string_maybe_quoted src_dir)
           ])
;;

let expand_include =
  (* CR-someday rgrinberg: move this into [Dune_project]? *)
  let dep_parser project =
    Dune_lang.Syntax.set
      Stanza.syntax
      (Active (Dune_project.dune_version project))
      (String_with_vars.set_decoding_env
         (* CR-someday rgrinberg: this environment looks fishy *)
         (Pform.Env.initial ~stanza:Stanza.latest_version ~extensions:[])
         (Bindings.decode Dep_conf.decode))
  in
  fun ~dir ~project s ->
    Path.Build.relative dir s
    |> Path.build
    |> Action_builder.read_sexp
    >>| function
    | Dune_lang.Ast.List (_loc, asts) ->
      List.concat_map
        asts
        ~f:(Dune_lang.Decoder.parse (dep_parser project) Univ_map.empty)
    | ast ->
      let loc = Dune_lang.Ast.loc ast in
      User_error.raise
        ~loc
        [ Pp.text "Dependency specification in `(include <filename>)` must be a list" ]
;;

let prepare_expander expander = Expander.set_expanding_what expander Deps_like_field

let add_sandbox_config acc (dep : Dep_conf.t) =
  match dep with
  | Sandbox_config cfg -> Sandbox_config.inter acc (make_sandboxing_config cfg)
  | _ -> acc
;;

let rec dir_contents ~loc d =
  let open Memo.O in
  Fs_memo.dir_contents d
  >>= function
  | Error e -> Unix_error.Detailed.raise e
  | Ok contents ->
    Fs_memo.Dir_contents.to_list contents
    |> Memo.parallel_map ~f:(fun (entry, kind) ->
      let path = Path.Outside_build_dir.relative d entry in
      match kind with
      | Unix.S_REG -> Memo.return [ path ]
      | S_DIR -> dir_contents ~loc path
      | _ ->
        User_error.raise
          ~loc
          [ Pp.text "Encountered a special file while expanding dependency." ])
    >>| List.concat
;;

let package loc pkg_name (context : Build_context.t) ~dune_version =
  Action_builder.of_memo
    (let open Memo.O in
     let* package_db = Package_db.create context.name in
     Package_db.find_package package_db pkg_name)
  >>= function
  | Some (Build build) -> build
  | Some (Local pkg) ->
    let open Action_builder.O in
    let* files =
      Action_builder.of_memo
        (let open Memo.O in
         let* sctx = Super_context.find_exn context.name in
         Install_layout.layout_files sctx [ pkg_name ])
    in
    let* () = Action_builder.paths files in
    (* Alias kept to populate _build/install/ for PATH and other env vars
       that still depend on the install staging directory. *)
    Alias_builder.alias (package_install ~context ~pkg)
  | Some (Installed pkg) ->
    if dune_version < (2, 9)
    then
      Action_builder.fail
        { fail =
            (fun () ->
              User_error.raise
                ~loc
                [ Pp.textf
                    "Dependency on an installed package requires at least (lang dune 2.9)"
                ])
        }
    else
      (let open Memo.O in
       Memo.parallel_map pkg.files ~f:(fun (s, l) ->
         let dir = Section.Map.find_exn pkg.sections s in
         Memo.parallel_map l ~f:(fun { kind; dst } ->
           let path = Path.append_local dir (Install.Entry.Dst.local dst) in
           match kind with
           | File -> Memo.return [ path ]
           | Directory ->
             Path.as_outside_build_dir_exn path
             |> dir_contents ~loc
             >>| List.rev_map ~f:Path.outside_build_dir)
         >>| List.concat)
       >>| List.concat)
      |> Action_builder.of_memo
      >>= Action_builder.paths
  | None ->
    Action_builder.fail
      { fail =
          (fun () ->
            User_error.raise
              ~loc
              [ Pp.textf "Package %s does not exist" (Package.Name.to_string pkg_name) ])
      }
;;

let rec dep expander : Dep_conf.t -> _ = function
  | Include s ->
    (* TODO this is wrong. we shouldn't allow bindings here if we are in an
       unnamed expansion *)
    let dir = Expander.dir expander in
    Other
      (let* deps =
         let* project = Action_builder.of_memo @@ Dune_load.find_project ~dir in
         expand_include ~dir ~project s
       in
       let builder, _bindings, _package_env = named_paths_builder ~expander deps in
       builder)
  | File s ->
    (match Expander.With_deps_if_necessary.expand_path expander s with
     | Without paths ->
       (* This special case is to support this pattern:

          {v
... (deps (:x foo)) (action (... (diff? %{x} %{x}.corrected))) ...
          v}

          Indeed, the second argument of [diff?] must be something that can be
          evaluated at rule production time since the dependency/target inferrer
          treats this argument as "consuming a target", and targets must be known
          at rule production time. This is not compatible with computing its
          expansion in the action builder monad, which is evaluated at rule
          execution time. *)
       Simple paths
     | With paths ->
       Other
         (let* paths = paths in
          let+ () = Action_builder.all_unit (List.map ~f:Action_builder.path paths) in
          paths))
  | Alias s ->
    Other
      (let* a = make_alias expander s in
       let+ () = Alias_builder.alias a in
       [])
  | Alias_rec s ->
    Other
      (let* a = make_alias expander s in
       let+ () = dep_on_alias_rec ~loc:(String_with_vars.loc s) a in
       [])
  | Glob_files glob_files ->
    Other
      (Glob_files_expand.action_builder
         glob_files
         ~f:(Expander.expand ~mode:Single expander)
         ~base_dir:(Expander.dir expander)
       >>| Glob_files_expand.Expanded.matches
       >>| List.map ~f:(fun path ->
         if Filename.is_relative path
         then Path.Build.relative (Expander.dir expander) path |> Path.build
         else Path.of_string path))
  | Source_tree s ->
    Other
      (let* path = Expander.expand_path expander s in
       let deps = Source_deps.files path in
       Action_builder.dyn_memo_deps deps |> Action_builder.map ~f:Path.Set.to_list)
  | Package p ->
    Other
      (let+ () =
         let* pkg_name = Expander.expand_str expander p >>| Package.Name.of_string in
         let context = Build_context.create ~name:(Expander.context expander) in
         let loc = String_with_vars.loc p in
         let* dune_version =
           Action_builder.of_memo
           @@
           let open Memo.O in
           Dune_load.find_project ~dir:(Expander.dir expander)
           >>| Dune_project.dune_version
         in
         package loc pkg_name context ~dune_version
       in
       [])
  | Universe ->
    Other
      (let+ () = Action_builder.dep Dep.universe in
       [])
  | Env_var var_sw ->
    Other
      (let* var = Expander.expand_str expander var_sw in
       let+ () = Action_builder.env_var var in
       [])
  | Sandbox_config _ -> Other (Action_builder.return [])

and combined_package_deps_builder expander pkgs =
  let open Action_builder.O in
  let context = Build_context.create ~name:(Expander.context expander) in
  let* classified =
    Action_builder.List.map pkgs ~f:(fun (swv, loc) ->
      let* name = Expander.expand_str expander swv in
      let pkg = Package.Name.of_string name in
      let+ found =
        Action_builder.of_memo
        @@
        let open Memo.O in
        let* package_db = Package_db.create context.name in
        Package_db.find_package package_db pkg
      in
      loc, pkg, found)
  in
  let local_packages =
    List.filter_map classified ~f:(fun (_, _, found) ->
      match found with
      | Some (Package_db.Local pkg) -> Some pkg
      | _ -> None)
  in
  let* env =
    match local_packages with
    | [] -> Action_builder.return Env.empty
    | _ ->
      let* layout =
        Action_builder.of_memo
        @@
        let open Memo.O in
        let* project = Dune_load.find_project ~dir:(Expander.dir expander) in
        let* all_packages = Dune_load.packages () in
        let package_names =
          if Dune_project.strict_package_deps project
          then
            let module Closure = Top_closure.Make (Package.Name.Set) (Monad.Id) in
            match
              Closure.top_closure local_packages ~key:Package.name ~deps:(fun pkg ->
                List.filter_map (Package.depends pkg) ~f:(fun dep ->
                  Package.Name.Map.find all_packages dep.name))
            with
            | Ok pkgs -> List.map pkgs ~f:Package.name
            | Error cycle ->
              User_error.raise
                [ Pp.text "Cycle in package dependencies:"
                ; Pp.chain cycle ~f:(fun pkg ->
                    Pp.text (Package.Name.to_string (Package.name pkg)))
                ]
          else Package.Name.Map.keys all_packages
        in
        let* sctx = Super_context.find_exn context.name in
        let lib_root = Install_layout.layout_lib_root sctx package_names in
        let+ files = Install_layout.layout_files sctx package_names in
        files, lib_root
      in
      let files, lib_root = layout in
      let+ () = Action_builder.paths files in
      Env.update Env.empty ~var:Dune_findlib.Config.ocamlpath_var ~f:(fun _PATH ->
        Some
          (Bin.cons_path
             ~path_sep:Dune_findlib.Config.ocamlpath_sep
             (Path.build lib_root)
             ~_PATH))
  in
  let* dune_version =
    Action_builder.of_memo
    @@
    let open Memo.O in
    Dune_load.find_project ~dir:(Expander.dir expander) >>| Dune_project.dune_version
  in
  let+ () =
    Action_builder.List.iter classified ~f:(fun (loc, pkg_name, found) ->
      match found with
      | Some (Local _) -> Action_builder.return ()
      | Some (Build build) -> build
      | Some (Installed _) | None -> package loc pkg_name context ~dune_version)
  in
  env

and named_paths_builder ~expander l =
  let builders, bindings, combined_packages_builder =
    let expander = prepare_expander expander in
    let package_swvs =
      List.filter_map l ~f:(function
        | Bindings.Unnamed (Dep_conf.Package p) -> Some (p, String_with_vars.loc p)
        | _ -> None)
    in
    let combined_packages_builder =
      match package_swvs with
      | [] -> None
      | pkgs -> Some (combined_package_deps_builder expander pkgs)
    in
    let builders, bindings =
      List.fold_left l ~init:([], Pform.Map.empty) ~f:(fun (builders, bindings) x ->
        match x with
        | Bindings.Unnamed (Dep_conf.Package _)
          when Option.is_some combined_packages_builder -> builders, bindings
        | Bindings.Unnamed x -> to_action_builder (dep expander x) :: builders, bindings
        | Named (name, x) ->
          let x = List.map x ~f:(dep expander) in
          (match
             Option.List.all
               (List.map x ~f:(function
                  | Simple x -> Some x
                  | Other _ -> None))
           with
           | Some x ->
             let open Memo.O in
             let x = Memo.lazy_ (fun () -> Memo.all_concurrently x >>| List.concat) in
             let bindings =
               Pform.Map.set
                 bindings
                 (Var (User_var name))
                 (Expander.Deps.Without (Memo.Lazy.force x >>| Value.L.paths))
             in
             let x =
               let open Action_builder.O in
               let* x = Action_builder.of_memo (Memo.Lazy.force x) in
               let+ () = Action_builder.paths x in
               x
             in
             x :: builders, bindings
           | None ->
             let x =
               Action_builder.memoize
                 ~cutoff:(List.equal Path.equal)
                 ("dep " ^ name)
                 (Action_builder.List.concat_map x ~f:to_action_builder)
             in
             let bindings =
               Pform.Map.set
                 bindings
                 (Var (User_var name))
                 (Expander.Deps.With (x >>| Value.L.paths))
             in
             x :: builders, bindings))
    in
    builders, bindings, combined_packages_builder
  in
  let builders, package_env =
    match combined_packages_builder with
    | None -> builders, Action_builder.return Env.empty
    | Some b ->
      let open Action_builder.O in
      let b = Action_builder.memoize "combined-package-deps" b in
      (* Include b in the builders list to ensure its deps are registered.
         The result (Env.t) is discarded here — it is returned separately
         as package_env. Memoization ensures b is evaluated only once. *)
      (b >>| fun _ -> []) :: builders, b
  in
  let builder = List.rev builders |> Action_builder.all >>| List.concat in
  builder, bindings, package_env
;;

let named sandbox ~expander l =
  let builder, bindings, package_env = named_paths_builder ~expander l in
  let builder =
    Action_builder.memoize
      ~cutoff:(List.equal Value.equal)
      "deps"
      (builder >>| Value.L.paths)
  in
  let bindings = Pform.Map.set bindings (Var Deps) (Expander.Deps.With builder) in
  let expander = Expander.add_bindings_full expander ~bindings in
  let sandbox =
    let open Action_builder.O in
    let rec sandbox_dep acc = function
      | Dep_conf.Include s ->
        let* deps =
          let dir = Expander.dir expander in
          let* project = Action_builder.of_memo (Dune_load.find_project ~dir) in
          expand_include ~dir ~project s
        in
        sandbox_bindings acc deps
      | dep -> Action_builder.return (add_sandbox_config acc dep)
    and sandbox_bindings acc deps =
      Bindings.fold deps ~init:(Action_builder.return acc) ~f:(fun one acc ->
        let* acc = acc in
        match one with
        | Unnamed dep -> sandbox_dep acc dep
        | Named (_, deps) -> Action_builder.List.fold_left deps ~init:acc ~f:sandbox_dep)
    in
    sandbox_bindings sandbox l
    |> Action_builder.memoize ~cutoff:Sandbox_config.equal "deps sandbox"
  in
  Action_builder.ignore builder, expander, sandbox, package_env
;;

let unnamed sandbox ~expander l =
  let expander = prepare_expander expander in
  let package_swvs =
    List.filter_map l ~f:(function
      | Dep_conf.Package p -> Some (p, String_with_vars.loc p)
      | _ -> None)
  in
  let package_env =
    match package_swvs with
    | [] -> Action_builder.return Env.empty
    | pkgs ->
      let open Action_builder.O in
      combined_package_deps_builder expander pkgs >>| Fun.id
  in
  ( List.fold_left l ~init:(Action_builder.return ()) ~f:(fun acc x ->
      let+ () = acc
      and+ _x = to_action_builder (dep expander x) in
      ())
  , List.fold_left l ~init:sandbox ~f:add_sandbox_config
  , package_env )
;;

let unnamed_get_paths ~expander l =
  let expander = prepare_expander expander in
  ( (let+ paths =
       List.fold_left l ~init:(Action_builder.return []) ~f:(fun acc x ->
         let+ acc = acc
         and+ paths = to_action_builder (dep expander x) in
         paths :: acc)
     in
     Path.Set.of_list (List.concat paths))
  , List.fold_left l ~init:None ~f:(fun acc (config : Dep_conf.t) ->
      match acc, config with
      | None, Sandbox_config _ ->
        Some
          (add_sandbox_config
             (Option.value ~default:Sandbox_config.no_special_requirements acc)
             config)
      | _, _ -> acc) )
;;
