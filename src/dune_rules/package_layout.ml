open Import
open Action_builder.O

let materialize_ordered context names =
  let packages = Package.Name.Set.of_list names in
  let prefix = Install_layout.root context packages |> Path.build in
  let* dependencies =
    Action_builder.List.map names ~f:(fun name ->
      let* mounted =
        Action_builder.of_memo (Pkg_sources.find_mounted_kind context name)
      in
      match mounted with
      | Some (mounted, `Opam) ->
        let* dependency =
          Action_builder.of_memo
            (Pkg_rules.dependency context (Pkg_sources.Mounted.candidate mounted))
        in
        dependency
      | Some (mounted, `Dune) ->
        let candidate = Pkg_sources.Mounted.candidate mounted in
        let { Dune_pkg.Lock_dir.Pkg.info; exported_env; _ } =
          Pkg_sources.Candidate.lock_pkg candidate
        in
        let paths =
          Pkg_rules.candidate_paths candidate |> Pkg_rules.Paths.map_path ~f:Path.build
        in
        Action_builder.return
          (Pkg_rules.Dependency.native
             paths
             ~prefix
             ~variables:(Dune_pkg.Lock_dir.Pkg_info.variables info)
             ~exported_env)
      | None ->
        let* package = Action_builder.of_memo (Dune_load.find_package context name) in
        (match package with
         | None ->
           User_error.raise
             [ Pp.textf "Package %s does not exist" (Package.Name.to_string name) ]
         | Some package ->
           let version =
             Package.version package |> Option.value ~default:Dune_pkg.Package_version.dev
           in
           let paths =
             Pkg_rules.Paths.of_root
               name
               ~root:prefix
               ~source_dir:"source"
               ~install_dir:"target"
               ~relative:Path.relative
           in
           let variables =
             Package_variable_name.Map.of_list_exn
               [ Package_variable_name.name, OpamVariable.S (Package.Name.to_string name)
               ; ( Package_variable_name.version
                 , S (Dune_pkg.Package_version.to_string version) )
               ; Package_variable_name.dev, B false
               ]
           in
           Action_builder.return
             (Pkg_rules.Dependency.native paths ~prefix ~variables ~exported_env:[])))
  in
  Pkg_rules.Layout.materialize context dependencies
;;

let materialize context packages =
  materialize_ordered context (Package.Name.Set.to_list packages)
;;

let materialize_dependencies context owner =
  let* direct, ordered =
    Action_builder.of_memo
      (let open Memo.O in
       let* workspace = Dune_load.packages ()
       and* candidates = Pkg_sources.candidates context in
       let candidates =
         Package.Name.Map.of_list_map_exn candidates ~f:(fun candidate ->
           Pkg_sources.Candidate.name candidate, candidate)
       in
       let versions =
         Package.Name.Map.union_exn
           (Package.Name.Map.map workspace ~f:(fun package ->
              Package.version package
              |> Option.value ~default:Dune_pkg.Package_version.dev))
           (Package.Name.Map.map candidates ~f:(fun candidate ->
              (Pkg_sources.Candidate.lock_pkg candidate).info.version))
       in
       let* polled = Lock_dir.Sys_vars.solver_env in
       let* active = Lock_dir.lock_dir_active context in
       let+ recorded =
         if not active
         then Memo.return Dune_pkg.Solver_env.empty
         else
           let+ lock_dir = Lock_dir.get_exn context in
           Dune_pkg.Solver_stats.Expanded_variable_bindings.to_solver_env
             lock_dir.expanded_solver_variable_bindings
       in
       let solver_env =
         Dune_pkg.Solver_env.extend
           (Dune_pkg.Solver_env.extend Dune_pkg.Solver_env.with_defaults polled)
           recorded
       in
       let system_dune name = Package.Name.equal name Dune_pkg.Dune_dep.name in
       let dependencies name =
         match Package.Name.Map.find workspace name with
         | Some package ->
           (match
              Dune_pkg.Lock_pkg.local_package_dependencies_with_depopts
                (Dune_pkg.Local_package.of_package package
                 |> Dune_pkg.Local_package.for_solver)
                ~env:(Dune_pkg.Solver_env.to_env solver_env)
                ~with_test:false
                ~packages:versions
                ~dune_version:
                  (Dune_pkg.Package_version.of_opam_package_version
                     Dune_pkg.Dune_dep.version)
            with
            | Ok dependencies -> dependencies
            | Error (`Formula_could_not_be_satisfied hints) ->
              User_error.raise
                ~loc:(Package.loc package)
                (Pp.textf
                   "The dependencies of package %S could not be satisfied:"
                   (Package.Name.to_string name)
                 :: List.map
                      hints
                      ~f:Dune_pkg.Resolve_opam_formula.Unsatisfied_formula_hint.pp))
         | None ->
           (match Package.Name.Map.find candidates name with
            | None ->
              User_error.raise
                [ Pp.textf "Package %s does not exist" (Package.Name.to_string name) ]
            | Some candidate ->
              let pkg = Pkg_sources.Candidate.lock_pkg candidate in
              Dune_pkg.Lock_dir.Conditional_choice.choose_for_platform
                pkg.depends
                ~platform:polled
              |> Option.value ~default:[]
              |> List.filter_map ~f:(fun (dep : Dune_pkg.Lock_dir.Dependency.t) ->
                Option.some_if (not (system_dune dep.name)) dep.name))
       in
       let direct = dependencies owner in
       let module Closure = Top_closure.Make (Package.Name.Set) (Monad.Id) in
       match Closure.top_closure ~key:Fun.id ~deps:dependencies direct with
       | Ok ordered -> Package.Name.Set.of_list direct, ordered
       | Error cycle ->
         User_error.raise
           [ Pp.text "Dependency cycle between packages:"
           ; Pp.chain cycle ~f:(fun name -> Pp.verbatim (Package.Name.to_string name))
           ])
  in
  let+ layout = materialize_ordered context ordered in
  direct, layout
;;
