open Import
open Memo.O
module Gen_rules = Build_config.Gen_rules
module Lock_pkg = Dune_pkg.Lock_dir.Pkg

let artifact_dir_basename = "pkg"

module Candidate = struct
  type t =
    { lock_pkg : Lock_pkg.t
    ; identity_digest : Dune_digest.t
    ; source_root : Path.Build.t option
    ; artifact_root : Path.Build.t
    }

  let name t = t.lock_pkg.info.name
  let source_root t = t.source_root
  let lock_pkg t = t.lock_pkg
  let artifact_root t = t.artifact_root
  let identity_digest t = t.identity_digest

  let make context lock_pkg =
    let identity_digest =
      Dune_digest.Feed.compute_digest Lock_pkg.digest_feed (Lock_pkg.remove_locs lock_pkg)
    in
    let id =
      sprintf
        "%s.%s-%s"
        (Package.Name.to_string lock_pkg.info.name)
        (Package_version.to_string lock_pkg.info.version)
        (Dune_digest.to_string identity_digest)
    in
    let mounted_context = Context_name.build_dir (Mounted_context.make context) in
    let source_root =
      Option.map lock_pkg.info.source ~f:(fun source ->
        Fetch_rules.target source `Directory)
    in
    let artifact_root =
      Path.Build.L.relative mounted_context [ artifact_dir_basename; id ]
    in
    { lock_pkg; identity_digest; source_root; artifact_root }
  ;;
end

module Mounted = struct
  type kind =
    | Dune
    | Opam of Opam_stanza.t

  type t =
    { candidate : Candidate.t
    ; source_root : Path.Build.t
    ; projects : (Dune_project.t * Source_tree.Rules.Dir.t) list
    ; tree : Source_tree.Rules.Build.t
    ; kind : kind
    }

  let candidate t = t.candidate
  let source_root t = t.source_root
  let projects t = t.projects
  let tree t = t.tree
  let kind t = t.kind

  let is_dune t =
    match t.kind with
    | Dune -> true
    | Opam _ -> false
  ;;
end

let load_candidates context =
  let* active = Lock_dir.lock_dir_active context in
  if not active
  then Memo.return []
  else
    let* lock_dir = Lock_dir.get_exn context
    and* platform = Lock_dir.Sys_vars.solver_env in
    Dune_pkg.Lock_dir.Packages.pkgs_on_platform_by_name lock_dir.packages ~platform
    |> Package.Name.Map.values
    |> List.map ~f:(Candidate.make context)
    |> Memo.return
;;

let candidates =
  Per_context.create_by_name ~name:"mounted-package-candidates" load_candidates
  |> Staged.unstage
;;

let selected_recipe candidate =
  let* platform = Lock_dir.Sys_vars.solver_env in
  let lock_pkg = candidate.Candidate.lock_pkg in
  let build =
    Dune_pkg.Lock_dir.Conditional_choice.choose_for_platform
      lock_pkg.build_command
      ~platform
  in
  let install =
    Dune_pkg.Lock_dir.Conditional_choice.choose_for_platform
      lock_pkg.install_command
      ~platform
  in
  let dependencies =
    Dune_pkg.Lock_dir.Conditional_choice.choose_for_platform lock_pkg.depends ~platform
    |> Option.value ~default:[]
  in
  Memo.return (build, install, dependencies)
;;

module Build_source_tree = Source_tree.Rules.Build

let load_source = Build_source_tree.load

let mount candidate source_root tree =
  let projects = Build_source_tree.projects tree in
  let package = Candidate.name candidate in
  let* represents_package =
    Memo.List.exists projects ~f:(fun (project, _) ->
      match
        Package.Name.Map.find (Dune_project.including_hidden_packages project) package
      with
      | None -> Memo.return false
      | Some package -> Package_enabled.eval package)
  in
  if not represents_package
  then Memo.return None
  else (
    let projects =
      List.map projects ~f:(fun (project, source_dir) ->
        ( Dune_project.set_package_version
            project
            ~package
            ~version:candidate.lock_pkg.info.version
          |> Dune_project.filter_packages ~f:(Package.Name.equal package)
        , source_dir ))
    in
    Memo.return (Some { Mounted.candidate; source_root; projects; tree; kind = Dune }))
;;

module Scan_dune_files = Source_tree.Rules.Dir.Make_map_reduce (Memo) (Monoid.Exists)

let has_dune_file tree =
  Scan_dune_files.map_reduce
    (Build_source_tree.root tree)
    ~traverse:Source_dir_status.Set.all
    ~trace_event_name:"Package source classification"
    ~f:(fun dir -> Memo.return (Option.is_some (Source_tree.Rules.Dir.dune_file dir)))
;;

let make_package candidate source_root dependencies =
  let { Lock_pkg.info; _ } = Candidate.lock_pkg candidate in
  let dir = Source_path.build source_root in
  Package.create
    ~name:info.name
    ~loc:Loc.none
    ~version:(Some info.version)
    ~conflicts:[]
    ~depends:
      (List.map dependencies ~f:(fun { Dune_pkg.Lock_dir.Dependency.name; _ } ->
         { Package_dependency.name; constraint_ = None }))
    ~depopts:[]
    ~enabled_if:None
    ~info:Package_info.empty
    ~has_opam_file:(Exists false)
    ~dir
    ~sites:Site.Map.empty
    ~allow_empty:true
    ~synopsis:None
    ~description:None
    ~tags:[]
    ~original_opam_file:None
    ~deprecated_package_names:Package.Name.Map.empty
    ~contents_basename:None
;;

let make_opam candidate source_root tree =
  let* build, install, dependencies = selected_recipe candidate in
  let package = make_package candidate source_root dependencies in
  let project =
    Dune_project.anonymous
      ~dir:(Source_path.build source_root)
      Package_info.empty
      (Package.Name.Map.singleton (Package.name package) package)
  in
  let stanza =
    { Opam_stanza.loc = Loc.none
    ; origin = Lock
    ; package
    ; depends =
        List.map dependencies ~f:(fun { Dune_pkg.Lock_dir.Dependency.loc; name } ->
          loc, name)
    ; build
    ; install
    ; depexts = candidate.lock_pkg.depexts
    ; exported_env = candidate.lock_pkg.exported_env
    }
  in
  { Mounted.candidate
  ; source_root
  ; projects = [ project, Build_source_tree.root tree ]
  ; tree
  ; kind = Opam stanza
  }
  |> Memo.return
;;

let prepare candidate =
  match Candidate.source_root candidate with
  | None -> Memo.return None
  | Some source_root ->
    let* tree = load_source source_root in
    let* has_dune_file = has_dune_file tree in
    if has_dune_file
    then mount candidate source_root tree
    else make_opam candidate source_root tree >>| Option.some
;;

let load_mounted context =
  let start = Time.now () in
  let+ mounted =
    candidates context >>= Memo.parallel_map ~f:prepare >>| List.filter_opt
  in
  Dune_trace.emit Pkg (fun () ->
    Dune_trace.Event.mounted_packages_load
      ~start
      ~stop:(Time.now ())
      ~context:(Context_name.to_string context)
      ~mounted:(List.length mounted));
  mounted
;;

let mounted =
  let by_context =
    Per_context.create_by_name ~name:"mounted-packages" (fun context ->
      Memo.Lazy.create ~name:"mounted-packages-for-context" (fun () ->
        load_mounted context)
      |> Memo.Lazy.force)
    |> Staged.unstage
  in
  fun context -> by_context context
;;

let find_mounted context name =
  let+ mounted = mounted context in
  List.find mounted ~f:(fun mounted ->
    Package.Name.equal name (Candidate.name (Mounted.candidate mounted)))
;;

let source_copy_rule ~dir ~source_dir filename =
  let src =
    Source_tree.Rules.Dir.file source_dir filename |> Source_tree.Rules.File.path
  in
  let dst = Path.Build.relative_fname dir filename in
  let { Action_builder.With_targets.build; targets } = Action_builder.copy ~src ~dst in
  Rule.make ~info:(Rule.Info.Source_file_copy src) ~targets build
;;

let add_artifact_source_rules ~dir ~source_dir rules =
  Gen_rules.map_rules rules ~f:(fun generated ->
    let rules =
      let* generated_rules = generated.rules in
      let generated_here =
        Rules.find generated_rules (Path.build dir) |> Rules.Dir_rules.consume
      in
      let selected =
        Dune_engine.Source_selection.select
          ~dir
          ~source_dir:(Source_tree.Rules.Dir.path source_dir)
          ~build_dir_only_sub_dirs:
            (Gen_rules.Build_only_sub_dirs.find generated.build_dir_only_sub_dirs dir)
          ~source_filenames:(Source_tree.Rules.Dir.filenames source_dir)
          ~source_dirs:(Source_tree.Rules.Dir.sub_dir_names source_dir)
          generated_here.rules
      in
      let selected_rules = Rule.Set.of_list selected.rules in
      let generated_rules =
        Rules.filter_rules generated_rules ~f:(fun rule ->
          (not (Path.Build.equal rule.targets.root dir))
          || Rule.Set.mem selected_rules rule)
        |> Rules.map_rules ~f:(fun (rule : Rule.t) ->
          match rule.mode with
          | Promote _ -> Rule.set_mode rule Standard
          | Standard | Fallback | Ignore_source_files -> rule)
      in
      let source_rules =
        Filename.Array.Set.to_list_map selected.source_filenames ~f:(fun filename ->
          source_copy_rule ~dir ~source_dir filename)
        |> Rules.of_rules
      in
      Memo.return (Rules.union source_rules generated_rules)
    in
    { generated with rules })
;;
