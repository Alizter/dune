open Import
open Memo.O
module Gen_rules = Build_config.Gen_rules
module Lock_pkg = Dune_pkg.Lock_dir.Pkg
module Build_command = Dune_pkg.Lock_dir.Build_command

let artifact_dir_basename = "pkg"

module Candidate = struct
  type t =
    { lock_pkg : Lock_pkg.t
    ; identity_digest : Dune_digest.t
    ; source_root : Path.Build.t option
    ; artifact_root : Path.Build.t
    }

  let name t = t.lock_pkg.info.name
  let source t = t.lock_pkg.info.source
  let source_root t = t.source_root
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
  type t =
    { candidate : Candidate.t
    ; source_root : Path.Build.t
    ; projects : (Dune_project.t * Source_tree.Rules.Dir.t) list
    ; tree : Source_tree.Rules.Build.t
    }

  let candidate t = t.candidate
  let source_root t = t.source_root
  let projects t = t.projects
  let tree t = t.tree
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

let literal = function
  | Dune_lang.Slang.Literal value -> String_with_vars.text_only value
  | _ -> None
;;

(* Arguments may contain package variables and filtered targets. Replacing the
   action is safe when its literal target includes the package install alias. *)
let is_dune_build = function
  | program :: command :: args ->
    Option.equal String.equal (literal program) (Some "dune")
    && Option.equal String.equal (literal command) (Some "build")
    && List.exists args ~f:(fun arg ->
      Option.equal String.equal (literal arg) (Some "@install"))
  | [] | [ _ ] -> false
;;

(* Condition-guarded steps such as [dune subst] for development packages do not
   veto mounting. At least one unconditional [dune build] is still required. *)
type action_kind =
  | No_unconditional_action
  | Dune_only
  | Other

let combine_action_kinds actions =
  List.fold_left actions ~init:No_unconditional_action ~f:(fun kind action ->
    match kind, action with
    | Other, _ | _, Other -> Other
    | Dune_only, _ | _, Dune_only -> Dune_only
    | No_unconditional_action, No_unconditional_action -> No_unconditional_action)
;;

let rec action_kind (action : Dune_lang.Action.t) =
  match action with
  | Run args | Runexec args -> if is_dune_build args then Dune_only else Other
  | Chdir (_, action)
  | No_infer action
  | Setenv (_, _, action)
  | Withenv (_, action)
  | With_accepted_exit_codes (_, action) -> action_kind action
  | Progn actions | Concurrent actions ->
    List.map actions ~f:action_kind |> combine_action_kinds
  | When _ -> No_unconditional_action
  | Dynamic_run _
  | Redirect_out _
  | Redirect_in _
  | Ignore _
  | Echo _
  | Cat _
  | Copy _
  | Symlink _
  | Copy_and_add_line_directive _
  | System _
  | Bash _
  | Write_file _
  | Mkdir _
  | Diff _
  | Pipe _
  | Cram _
  | Patch _
  | Substitute _
  | Format_dune_file _ -> Other
;;

let build_command_is_dune_only = function
  | Build_command.Dune -> true
  | Build_command.Action action ->
    (match action_kind action with
     | Dune_only -> true
     | No_unconditional_action | Other -> false)
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
  let depends_on_dune =
    Dune_pkg.Lock_dir.Conditional_choice.choose_for_platform lock_pkg.depends ~platform
    |> Option.value ~default:[]
    |> List.exists ~f:(fun { Dune_pkg.Lock_dir.Dependency.name; _ } ->
      Package.Name.equal name (Package.Name.of_string "dune"))
  in
  Memo.return (build, install, depends_on_dune)
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
    Memo.return (Some { Mounted.candidate; source_root; projects; tree }))
;;

let prepare candidate =
  let* build, install, depends_on_dune = selected_recipe candidate in
  let recipe_is_dune_only =
    match build, install with
    | Some build, None ->
      build_command_is_dune_only build && List.is_empty candidate.lock_pkg.depexts
    | Some _, Some _ | None, _ -> false
  in
  (* A selected dependency on Dune is deliberately authoritative: native rule
     generation replaces the complete recorded build and install recipe. *)
  let mount_recipe = depends_on_dune || recipe_is_dune_only in
  match
    ( mount_recipe && List.is_empty candidate.lock_pkg.info.extra_sources
    , Candidate.source candidate
    , Candidate.source_root candidate )
  with
  | true, Some source, Some source_root ->
    Lock_dir.source_kind source
    >>= (function
     | `Local (`File, _) ->
       let* tree = load_source source_root in
       mount candidate source_root tree
     | `Fetch when (snd source.url).backend = `http ->
       let* tree = load_source source_root in
       mount candidate source_root tree
     | `Local (`Directory, _) | `Fetch -> Memo.return None)
  | false, _, _ | true, Some _, None | true, None, _ -> Memo.return None
;;

let mounted =
  let by_context =
    Per_context.create_by_name ~name:"mounted-packages" (fun context ->
      candidates context >>= Memo.parallel_map ~f:prepare >>| List.filter_opt)
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
