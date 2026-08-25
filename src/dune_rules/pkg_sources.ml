open Import
open Memo.O
module Gen_rules = Build_config.Gen_rules
module Lock_pkg = Dune_pkg.Lock_dir.Pkg
module Build_command = Dune_pkg.Lock_dir.Build_command

let source_dir_basename = ".pkg-source"
let artifact_dir_basename = "pkg"

module Candidate = struct
  type t =
    { lock_pkg : Lock_pkg.t
    ; identity_digest : Dune_digest.t
    ; source_id : string
    ; source_root : Path.Build.t
    ; artifact_root : Path.Build.t
    }

  let name t = t.lock_pkg.info.name
  let source t = t.lock_pkg.info.source
  let source_root t = t.source_root
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
    let source_root =
      Path.Build.L.relative
        Private_context.t.build_dir
        [ Context_name.to_string context; source_dir_basename; source_id ]
    in
    let artifact_root =
      Path.Build.L.relative
        (Context_name.build_dir (Mounted_context.make context))
        [ artifact_dir_basename; id ]
    in
    { lock_pkg; identity_digest; source_id; source_root; artifact_root }
  ;;
end

module Mounted = struct
  type t =
    { candidate : Candidate.t
    ; projects : Dune_project.t list
    ; dune_files : (Source_path.t * Dune_project.t * Source.Dune_file.t) Appendable_list.t
    }

  let candidate t = t.candidate
  let projects t = t.projects
  let dune_files t = t.dune_files
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

let is_dune_build = function
  | program :: command :: args ->
    Option.equal String.equal (literal program) (Some "dune")
    && Option.equal String.equal (literal command) (Some "build")
    && List.for_all args ~f:(fun arg -> Option.is_some (literal arg))
  | [] | [ _ ] -> false
;;

let rec action_is_dune_only (action : Dune_lang.Action.t) =
  match action with
  | Run args -> is_dune_build args
  | Chdir (_, action)
  | No_infer action
  | Setenv (_, _, action)
  | Withenv (_, action)
  | With_accepted_exit_codes (_, action) -> action_is_dune_only action
  | Progn actions | Concurrent actions ->
    (not (List.is_empty actions)) && List.for_all actions ~f:action_is_dune_only
  | Runexec _
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
  | When _
  | Format_dune_file _ -> false
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

module Loaded_source = struct
  type t =
    { projects : Dune_project.t list
    ; dune_files : (Source_path.t * Dune_project.t * Source.Dune_file.t) Appendable_list.t
    }
end

let load_source_impl package_source_root =
  let rec traverse
            ~source_dir
            ~build_dir
            ~status
            ~parent_dune_file
            ~parent_project
            ~physical
    =
    let* files, physical_subdirs =
      if physical
      then Build_system.directory_target_contents ~dir:build_dir
      else Memo.return (Filename.Array.Set.empty, Filename.Array.Set.empty)
    in
    let* loaded_project =
      match status, physical with
      | Source_dir_status.Data_only, _ | _, false -> Memo.return None
      | (Source_dir_status.Normal | Source_dir_status.Vendored), true ->
        Dune_project.gen_load_source
          ~read:(fun path -> Build_system.read_file (Source_path.to_path path))
          ~dir:source_dir
          ~files
          ~infer_from_opam_files:false
          ~load_opam_file_with_contents:Dune_pkg.Opam_file.load_opam_file_with_contents
    in
    let project, projects =
      match loaded_project, parent_project with
      | Some project, _ -> project, [ project ]
      | None, Some project -> project, []
      | None, None ->
        let project =
          Dune_project.anonymous ~dir:source_dir Package_info.empty Package.Name.Map.empty
        in
        project, [ project ]
    in
    let* dune_file =
      Source.Dune_file.load_build
        ~dir:build_dir
        status
        project
        ~files
        ~parent:parent_dune_file
    in
    let sub_dirs_spec =
      match dune_file with
      | None -> Source_dir_status.Spec.default
      | Some dune_file -> Source.Dune_file.sub_dir_status dune_file
    in
    let all_subdirs =
      match dune_file with
      | None -> physical_subdirs
      | Some dune_file ->
        Filename.Array.Set.union
          physical_subdirs
          (Source.Dune_file.sub_dirnames dune_file)
    in
    let status_map = Source_dir_status.Spec.eval sub_dirs_spec ~dirs:all_subdirs in
    let here =
      match dune_file with
      | None -> []
      | Some dune_file -> [ source_dir, project, dune_file ]
    in
    let* children =
      Filename.Array.Set.to_list all_subdirs
      |> Memo.List.concat_map ~f:(fun basename ->
        let open Source_dir_status.Or_ignored in
        match Source_dir_status.Per_dir.status status_map ~dir:basename with
        | Ignored -> Memo.return []
        | Status child_status ->
          let child_status =
            match status, child_status with
            | Source_dir_status.Data_only, _ -> Source_dir_status.Data_only
            | Source_dir_status.Vendored, Source_dir_status.Normal ->
              Source_dir_status.Vendored
            | _, child_status -> child_status
          in
          let+ child_projects, child_dune_files =
            traverse
              ~source_dir:(Source_path.relative_fname source_dir basename)
              ~build_dir:(Path.Build.relative_fname build_dir basename)
              ~status:child_status
              ~parent_dune_file:dune_file
              ~parent_project:(Some project)
              ~physical:(Filename.Array.Set.mem physical_subdirs basename)
          in
          [ child_projects, child_dune_files ])
    in
    let child_projects, child_dune_files =
      List.fold_left
        children
        ~init:([], [])
        ~f:(fun (projects, dune_files) (child_projects, child_dune_files) ->
          projects @ child_projects, dune_files @ child_dune_files)
    in
    Memo.return (projects @ child_projects, here @ child_dune_files)
  in
  let source_dir = Source_path.build package_source_root in
  let+ projects, dune_files =
    traverse
      ~source_dir
      ~build_dir:package_source_root
      ~status:Source_dir_status.Vendored
      ~parent_dune_file:None
      ~parent_project:None
      ~physical:true
  in
  { Loaded_source.projects; dune_files = Appendable_list.of_list dune_files }
;;

let load_source =
  let memo =
    Memo.create "load-mounted-package-source" ~input:(module Path.Build) load_source_impl
  in
  fun candidate -> Memo.exec memo (Candidate.source_root candidate)
;;

let mount candidate ({ Loaded_source.projects; dune_files } : Loaded_source.t) =
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
    let projects_by_root =
      Source_path.Map.of_list_map_exn projects ~f:(fun project ->
        Dune_project.root project, project)
    in
    let dune_files =
      Appendable_list.map dune_files ~f:(fun (dir, project, dune_file) ->
        let project =
          Source_path.Map.find_exn projects_by_root (Dune_project.root project)
        in
        dir, project, dune_file)
    in
    Memo.return (Some { Mounted.candidate; projects; dune_files }))
;;

let prepare candidate =
  let* build, install = selected_action candidate in
  match build, install, Candidate.source candidate with
  | Some (Build_command.Action action), None, Some source
    when action_is_dune_only action
         && List.is_empty candidate.lock_pkg.depexts
         && List.is_empty candidate.lock_pkg.info.extra_sources ->
    Lock_dir.source_kind source
    >>= (function
     | `Local (`File, _) | `Fetch ->
       let* source = load_source candidate in
       mount candidate source
     | `Local (`Directory, _) -> Memo.return None)
  | Some (Build_command.Action _), None, Some _ -> Memo.return None
  | Some Build_command.Dune, _, _
  | None, _, _
  | Some (Build_command.Action _), Some _, _
  | Some (Build_command.Action _), None, None -> Memo.return None
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
          let target = Candidate.source_root candidate in
          let parent = Path.Build.parent_exn target in
          if not (Path.Build.equal parent dir)
          then
            Code_error.raise
              "Mounted package source rule requested at an unexpected path"
              [ "requested", Path.Build.to_dyn dir; "expected", Path.Build.to_dyn parent ];
          let loc = fst source.url in
          let directory_targets = Path.Build.Map.singleton target loc in
          let rules =
            Rules.collect_unit (fun () ->
              let { Action_builder.With_targets.build; targets } =
                Fetch_rules.fetch ~target `Directory source
              in
              Rule.make ~info:(Rule.Info.of_loc_opt (Some loc)) ~targets build
              |> Rules.Produce.rule)
          in
          Gen_rules.make ~directory_targets rules
        | `Local (`Directory, _) -> Gen_rules.no_rules))
;;

let setup_rules ~context ~dir ~components =
  match components with
  | [] ->
    let build_dir_only_sub_dirs =
      Gen_rules.Build_only_sub_dirs.singleton
        ~dir
        (Subdir_set.of_list [ Filename.of_string_exn source_dir_basename ])
    in
    Gen_rules.make ~build_dir_only_sub_dirs (Memo.return Rules.empty) |> Memo.return
  | [ component ] when String.equal component source_dir_basename ->
    let* candidates = candidates context in
    Memo.List.fold_left
      candidates
      ~init:(String.Set.empty, Gen_rules.no_rules)
      ~f:(fun (seen, rules) candidate ->
        let id = Candidate.source_id candidate in
        if String.Set.mem seen id
        then Memo.return (seen, rules)
        else
          let+ source_rules = source_rules ~context ~dir ~id in
          String.Set.add seen id, Gen_rules.combine rules source_rules)
    >>| snd
  | component :: _ :: _ when String.equal component source_dir_basename ->
    Gen_rules.redirect_to_parent Gen_rules.Rules.empty |> Memo.return
  | _ -> Gen_rules.rules_here Gen_rules.Rules.empty |> Memo.return
;;

let source_copy_rule ~dir ~source_dir filename =
  let src = Path.build (Path.Build.relative_fname source_dir filename) in
  let dst = Path.Build.relative_fname dir filename in
  let { Action_builder.With_targets.build; targets } = Action_builder.copy ~src ~dst in
  Rule.make ~info:(Rule.Info.Source_file_copy src) ~targets build
;;

let add_artifact_source_rules ~dir ~source_dir rules =
  Gen_rules.map_rules rules ~f:(fun generated ->
    let rules =
      let* source_filenames =
        Build_system.files_of ~dir:(Path.build source_dir) >>| Filename_set.filenames
      and* generated_rules = generated.rules in
      let generated_here =
        Rules.find generated_rules (Path.build dir) |> Rules.Dir_rules.consume
      in
      let selected =
        Dune_engine.Source_selection.select
          ~dir
          ~source_dir:(Path.build source_dir)
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
          source_copy_rule ~dir ~source_dir filename)
        |> Rules.of_rules
      in
      Memo.return (Rules.union source_rules generated_rules)
    in
    { generated with rules })
;;
