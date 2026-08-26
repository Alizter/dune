open Import
open Memo.O
module Gen_rules = Build_config.Gen_rules
module Lock_pkg = Dune_pkg.Lock_dir.Pkg
module Build_command = Dune_pkg.Lock_dir.Build_command

let archive_dir_basename = ".pkg-archive"
let artifact_dir_basename = "pkg"

module Candidate = struct
  type t =
    { lock_pkg : Lock_pkg.t
    ; identity_digest : Dune_digest.t
    ; source_id : string
    ; archive_file : Path.Build.t
    ; artifact_root : Path.Build.t
    }

  let name t = t.lock_pkg.info.name
  let source t = t.lock_pkg.info.source
  let archive_file t = t.archive_file
  let artifact_root t = t.artifact_root
  let identity_digest t = t.identity_digest
  let source_id t = t.source_id

  let make context lock_pkg =
    let identity_digest =
      Dune_digest.Feed.compute_digest Lock_pkg.digest_feed (Lock_pkg.remove_locs lock_pkg)
    in
    let source_digest =
      match lock_pkg.info.source with
      | None -> identity_digest
      | Some source ->
        Dune_digest.repr Dune_pkg.Source.repr (Dune_pkg.Source.remove_locs source)
    in
    let source_id = Dune_digest.to_string source_digest in
    let id =
      sprintf
        "%s.%s-%s"
        (Package.Name.to_string lock_pkg.info.name)
        (Package_version.to_string lock_pkg.info.version)
        (Dune_digest.to_string identity_digest)
    in
    let archive_file =
      Path.Build.L.relative
        Private_context.t.build_dir
        [ Context_name.to_string context; archive_dir_basename; source_id; "file" ]
    in
    let artifact_root =
      Path.Build.L.relative
        (Context_name.build_dir (Mounted_context.make context))
        [ artifact_dir_basename; id ]
    in
    { lock_pkg; identity_digest; source_id; archive_file; artifact_root }
  ;;
end

module Mounted = struct
  type t =
    { candidate : Candidate.t
    ; source : Loaded_source.t
    ; projects : Dune_project.t list
    ; tree : Source_tree.Rules.Loaded.t
    }

  let candidate t = t.candidate
  let source t = t.source
  let projects t = t.projects
  let tree t = t.tree
end

let candidates =
  let by_context =
    Per_context.create_by_name ~name:"mounted-package-candidates" (fun context ->
      let* active = Lock_dir.lock_dir_active context in
      if not active
      then Memo.return []
      else
        let* lock_dir = Lock_dir.get_exn context
        and* platform = Lock_dir.Sys_vars.solver_env in
        Dune_pkg.Lock_dir.Packages.pkgs_on_platform_by_name lock_dir.packages ~platform
        |> Package.Name.Map.values
        |> List.map ~f:(Candidate.make context)
        |> Memo.return)
    |> Staged.unstage
  in
  fun context -> by_context context
;;

let find_candidate context id =
  let+ candidates = candidates context in
  List.find candidates ~f:(fun candidate ->
    String.equal id (Candidate.source_id candidate))
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

let selected_action candidate =
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
  Memo.return (build, install)
;;

module Loaded_tree = Source_tree.Rules.Loaded

let load_source = Loaded_tree.load

let mount candidate source tree =
  let projects = Loaded_tree.projects tree in
  let package = Candidate.name candidate in
  let* represents_package =
    Memo.List.exists projects ~f:(fun project ->
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
      List.map projects ~f:(fun project ->
        Dune_project.set_package_version
          project
          ~package
          ~version:candidate.lock_pkg.info.version
        |> Dune_project.filter_packages ~f:(Package.Name.equal package))
    in
    Memo.return (Some { Mounted.candidate; source; projects; tree }))
;;

let prepare_snapshot candidate source =
  let archive_file = Candidate.archive_file candidate |> Path.build in
  let* archive =
    Build_system.with_file archive_file ~f:(fun path ->
      let filename =
        let url = snd source.Dune_pkg.Source.url in
        Filename.basename url.path |> Filename.of_string_exn
      in
      { Dune_pkg.Source_snapshot.Archive.path; filename; digest = Dune_digest.file path })
  in
  Dune_pkg.Source_snapshot.prepare archive
;;

let prepare candidate =
  let* build, install = selected_action candidate in
  match build, install, Candidate.source candidate with
  | Some build, None, Some source
    when build_command_is_dune_only build
         && List.is_empty candidate.lock_pkg.depexts
         && List.is_empty candidate.lock_pkg.info.extra_sources ->
    Lock_dir.source_kind source
    >>= (function
     | `Local (`File, _) ->
       let* snapshot = prepare_snapshot candidate source in
       let loaded_source =
         Loaded_source.create ~snapshot ~root:(Candidate.artifact_root candidate)
       in
       let* source = load_source loaded_source in
       mount candidate loaded_source source
     | `Fetch when (snd source.url).backend = `http ->
       let* snapshot = prepare_snapshot candidate source in
       let loaded_source =
         Loaded_source.create ~snapshot ~root:(Candidate.artifact_root candidate)
       in
       let* source = load_source loaded_source in
       mount candidate loaded_source source
     | `Local (`Directory, _) | `Fetch -> Memo.return None)
  | Some _, None, Some _ | Some _, Some _, _ | Some _, None, None | None, _, _ ->
    Memo.return None
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

let source_rules ~context ~dir ~id =
  let* candidate = find_candidate context id in
  match candidate with
  | None -> Memo.return Gen_rules.no_rules
  | Some candidate ->
    (match Candidate.source candidate with
     | None -> Memo.return Gen_rules.no_rules
     | Some source ->
       Lock_dir.source_kind source
       >>| (function
        | `Local (`File, _) | `Fetch ->
          let target = Candidate.archive_file candidate in
          let parent = Path.Build.parent_exn target in
          if not (Path.Build.equal parent dir)
          then
            Code_error.raise
              "Mounted package archive rule requested at an unexpected path"
              [ "requested", Path.Build.to_dyn dir; "expected", Path.Build.to_dyn parent ];
          let loc = fst source.url in
          let rules =
            Rules.collect_unit (fun () ->
              let { Action_builder.With_targets.build; targets } =
                Fetch_rules.fetch ~target `File source
              in
              Rule.make ~info:(Rule.Info.of_loc_opt (Some loc)) ~targets build
              |> Rules.Produce.rule)
          in
          Gen_rules.make rules
        | `Local (`Directory, _) -> Gen_rules.no_rules))
;;

let setup_rules ~context ~dir ~components =
  match components with
  | [] ->
    let build_dir_only_sub_dirs =
      Gen_rules.Build_only_sub_dirs.singleton
        ~dir
        (Subdir_set.of_list [ Filename.of_string_exn archive_dir_basename ])
    in
    Gen_rules.make ~build_dir_only_sub_dirs (Memo.return Rules.empty) |> Memo.return
  | [ component ] when String.equal component archive_dir_basename ->
    let+ candidates = candidates context in
    let subdirs =
      List.map candidates ~f:(fun candidate ->
        Candidate.source_id candidate |> Filename.of_string_exn)
      |> Subdir_set.of_list
    in
    Gen_rules.make_empty ~dir subdirs
  | [ component; id ] when String.equal component archive_dir_basename ->
    source_rules ~context ~dir ~id
  | component :: _ :: _ :: _ when String.equal component archive_dir_basename ->
    Gen_rules.redirect_to_parent Gen_rules.Rules.empty |> Memo.return
  | _ -> Gen_rules.rules_here Gen_rules.Rules.empty |> Memo.return
;;

let source_copy_rule ~dir ~source ~source_dir filename =
  let src =
    Path.Local.relative_fname source_dir filename |> Loaded_source.file_path source
  in
  let dst = Path.Build.relative_fname dir filename in
  let { Action_builder.With_targets.build; targets } = Action_builder.copy ~src ~dst in
  Rule.make ~info:(Rule.Info.Source_file_copy src) ~targets build
;;

let add_artifact_source_rules ~dir ~source ~source_dir rules =
  Gen_rules.map_rules rules ~f:(fun generated ->
    let rules =
      let* source_filenames =
        Loaded_source.readdir source source_dir
        >>| Filename.Map.foldi ~init:[] ~f:(fun name kind files ->
          match kind with
          | `File -> name :: files
          | `Dir -> files)
        >>| Filename.Array.Set.of_list
      and* generated_rules = generated.rules in
      let generated_here =
        Rules.find generated_rules (Path.build dir) |> Rules.Dir_rules.consume
      in
      let selected =
        Dune_engine.Source_selection.select
          ~dir
          ~source_dir:(Loaded_source.source_path source source_dir |> Path.build)
          ~build_dir_only_sub_dirs:
            (Gen_rules.Build_only_sub_dirs.find generated.build_dir_only_sub_dirs dir)
          ~source_filenames
          ~source_dirs:Filename.Array.Set.empty
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
          source_copy_rule ~dir ~source ~source_dir filename)
        |> Rules.of_rules
      in
      Memo.return (Rules.union source_rules generated_rules)
    in
    { generated with rules })
;;
