open Import
open Memo.O
module Backing = Source_tree_file.Backing

let package_of_dir_in_context dir =
  match Path.Local.explode dir |> Filename.L.to_string with
  | root :: name :: _
    when String.equal root (Filename.to_string Filename.pkg_dir_basename) ->
    Package.Name.of_string_opt name
  | _ -> None
;;

let package_of_artifact_path path =
  match Path.Build.split_first_component path with
  | None -> None
  | Some (_, dir) -> package_of_dir_in_context dir
;;

let disable_promotion_in_package ~dir action =
  match package_of_artifact_path dir with
  | None -> action
  | Some _ -> Action.Full.disable_promotion action
;;

let source_location path =
  match package_of_artifact_path path with
  | Some _ -> Path.build path
  | None -> Path.Build.drop_build_context_exn path |> Path.source
;;

module Source_input = struct
  type t =
    { files : (Path.t * Path.Local.t) list
    ; directories : Path.Local.t list
    }
end

module Candidate = struct
  type t =
    { lock_pkg : Dune_pkg.Lock_dir.Pkg.t
    ; files_dir : Path.Build.t
    ; artifact_root : Path.Build.t
    }

  let name t = t.lock_pkg.info.name

  let source_loc t =
    match t.lock_pkg.info.source with
    | None -> Loc.none
    | Some source -> fst source.url
  ;;

  let source_root t =
    match t.lock_pkg.info.source with
    | None -> Memo.return None
    | Some source ->
      let+ kind = Lock_dir.source_kind source >>| User_error.ok_exn in
      let root =
        match kind with
        | `Local (`Directory, path) -> Backing.Fs path
        | `Local (`File, _) | `Fetch ->
          Backing.Build (Fetch_rules.make_target ~kind:Dir source)
      in
      Some root
  ;;

  let lock_pkg t = t.lock_pkg
  let files_dir t = t.files_dir
  let artifact_root t = t.artifact_root

  let dependencies t =
    let+ platform = Lock_dir.Sys_vars.solver_env in
    Dune_pkg.Lock_dir.Conditional_choice.choose_for_platform t.lock_pkg.depends ~platform
    |> Option.value ~default:[]
    |> Package.Name.Set.of_list_map ~f:(fun (dep : Dune_pkg.Lock_dir.Dependency.t) ->
      dep.name)
  ;;
end

let candidates =
  Per_context.create_by_name ~name:"mounted-package-candidates" (fun context ->
    Memo.lazy_ ~name:"mounted-package-candidates" (fun () ->
      let* active = Lock_dir.lock_dir_active context in
      if not active
      then Memo.return Package.Name.Map.empty
      else
        let+ lock_dir = Lock_dir.get_exn context
        and+ lock_dir_path = Lock_dir.get_path context >>| Option.value_exn
        and+ platform = Lock_dir.Sys_vars.solver_env in
        Log.info "Package source candidates" [ "context", Context_name.to_dyn context ];
        Dune_pkg.Lock_dir.packages_on_platform lock_dir ~platform
        |> Package.Name.Map.map ~f:(fun (lock_pkg : Dune_pkg.Lock_dir.Pkg.t) ->
          let version =
            Option.some_if
              (Dune_pkg.Lock_dir.uses_versioned_paths lock_dir)
              lock_pkg.info.version
          in
          let files_dir =
            Dune_pkg.Lock_dir.Pkg.files_dir
              lock_pkg.info.name
              version
              ~lock_dir:lock_dir_path
            |> Path.as_in_build_dir_exn
          in
          let artifact_root =
            Path.Build.L.relative
              (Context_name.build_dir context)
              [ Filename.to_string Filename.pkg_dir_basename
              ; Package.Name.to_string lock_pkg.info.name
              ]
          in
          { Candidate.lock_pkg; files_dir; artifact_root }))
    |> Memo.Lazy.force)
  |> Staged.unstage
;;

let dependencies =
  Per_context.create_by_name ~name:"mounted-package-dependencies" (fun context ->
    Memo.lazy_ ~name:"mounted-package-dependencies" (fun () ->
      let* candidates = candidates context in
      (* Polling the platform runs commands; do not without a lock dir. *)
      if Package.Name.Map.is_empty candidates
      then Memo.return Package.Name.Map.empty
      else
        let+ platform = Lock_dir.Sys_vars.solver_env in
        Package.Name.Map.map candidates ~f:(fun candidate ->
          Dune_pkg.Lock_dir.Conditional_choice.choose_for_platform
            (Candidate.lock_pkg candidate).depends
            ~platform
          |> Option.value ~default:[]
          |> List.filter_map ~f:(fun (dep : Dune_pkg.Lock_dir.Dependency.t) ->
            Option.some_if
              (not (Package.Name.equal dep.name Dune_pkg.Dune_dep.name))
              dep.name)))
    |> Memo.Lazy.force)
  |> Staged.unstage
;;

let find_candidate context name =
  let+ candidates = candidates context in
  Package.Name.Map.find candidates name
;;

let listing root =
  let rec loop local =
    let dir = Backing.append_local root local in
    let* contents = Backing.dir_contents dir in
    match contents with
    | Error error -> Memo.return (Error error)
    | Ok None ->
      (match dir with
       | Backing.Build dir ->
         Code_error.raise
           "Package source directory was not produced"
           [ "dir", Path.Build.to_dyn dir ]
       | Fs dir ->
         Memo.return
           (Error (Unix.ENOENT, "readdir", Path.Outside_build_dir.to_string dir)))
    | Ok (Some (files, dirs)) ->
      let files =
        Filename.Array.Set.to_list files
        |> List.map ~f:(fun file ->
          ( Backing.relative_fname dir file |> Backing.path
          , Path.Local.relative_fname local file ))
      in
      let+ subdirs =
        Filename.Array.Set.to_list dirs
        |> Memo.List.map ~f:(fun dir -> loop (Path.Local.relative_fname local dir))
      in
      let open Result.O in
      let+ subdirs = Result.List.all subdirs in
      { Source_input.files =
          files @ List.concat_map subdirs ~f:(fun { Source_input.files; _ } -> files)
      ; directories =
          local
          :: List.concat_map subdirs ~f:(fun { Source_input.directories; _ } ->
            directories)
      }
  in
  loop Path.Local.root
;;

let listing =
  let memo = Memo.create "package-source-listing" ~input:(module Backing) listing in
  fun ~loc root ->
    let+ contents = Memo.exec memo root in
    match contents with
    | Ok contents -> contents
    | Error error -> Backing.unreadable ~loc root error
;;

let source candidate =
  let* root = Candidate.source_root candidate in
  match root with
  | None -> Memo.return { Source_input.files = []; directories = [] }
  | Some root -> listing ~loc:(Candidate.source_loc candidate) root
;;

module Mounted = struct
  type t =
    { candidate : Candidate.t
    ; loaded : (Source_tree.Dir.t option, User_message.t list) result
    }

  let candidate t = t.candidate

  let kind t =
    Result.map t.loaded ~f:(function
      | None -> `Opam
      | Some _ -> `Dune)
  ;;

  let kind_exn t =
    match kind t with
    | Ok kind -> Memo.return kind
    | Error messages ->
      List.map messages ~f:(fun message ->
        Exn_with_backtrace.capture (User_error.E message))
      |> Fiber.reraise_all
      |> Memo.of_reproducible_fiber
  ;;

  let tree t =
    match t.loaded with
    | Ok tree -> tree
    | Error _ -> None
  ;;
end

module Package_action = Dune_lang.Action

let dune_value : OpamVariable.variable_contents -> Value.t list = function
  | B b -> [ String (Bool.to_string b) ]
  | S s -> [ String s ]
  | L s -> List.map s ~f:(fun x -> Value.String x)
;;

type variable_resolution =
  | Resolved of OpamVariable.variable_contents option
  | Requires_package_build

let resolve_package_variable
      candidates
      candidate
      { Dune_pkg.Package_variable.scope; name }
  =
  let package =
    match scope with
    | Self -> Candidate.name candidate
    | Package package -> package
  in
  match Package.Name.Map.find candidates package with
  | None ->
    let+ packages = Dune_load.packages ()
    and+ direct = Candidate.dependencies candidate in
    if Package.Name.Set.mem direct package && Package.Name.Map.mem packages package
    then Requires_package_build
    else (
      let value =
        match Package_variable_name.to_string name with
        | "build-id" -> None
        | _ -> Lock_dir.default_package_variable ~present:false name
      in
      Resolved value)
  | Some package ->
    let variables =
      Dune_pkg.Lock_dir.Pkg_info.variables (Candidate.lock_pkg package).info
    in
    Memo.return
      (match
         Option.first_some
           (Package_variable_name.Map.find variables name)
           (Lock_dir.default_package_variable ~present:true name)
       with
       | Some value -> Resolved (Some value)
       | None -> Requires_package_build)
;;

let rec action_contains_source_transformation = function
  | Package_action.Patch _ | Substitute _ -> true
  | Progn actions | Concurrent actions | Pipe (_, actions) ->
    List.exists actions ~f:action_contains_source_transformation
  | With_accepted_exit_codes (_, action)
  | Chdir (_, action)
  | Setenv (_, _, action)
  | Redirect_out (_, _, _, action)
  | Redirect_in (_, _, action)
  | Ignore (_, action)
  | No_infer action
  | Withenv (_, action)
  | When (_, action) -> action_contains_source_transformation action
  | _ -> false
;;

(* Each action is paired with the environment updates in its scope, innermost
   first, so that it can be run outside of its [progn]. *)
let rec flatten_progn envs = function
  | Package_action.Progn actions -> List.concat_map actions ~f:(flatten_progn envs)
  | Withenv (env, action) -> flatten_progn (env :: envs) action
  | action -> [ envs, action ]
;;

let in_scope (envs, action) =
  List.fold_left envs ~init:action ~f:(fun action env ->
    Package_action.Withenv (env, action))
;;

let expand_condition_pform candidates candidate solver_env unsupported ~source = function
  | Pform.Var (Pkg variable) ->
    let values =
      match Lock_dir.global_variable ~solver_env variable with
      | Some value -> dune_value value
      | None ->
        unsupported := true;
        [ Value.String "" ]
    in
    Memo.return (Ok values)
  | Macro ({ macro = Pkg | Pkg_self; _ } as invocation) ->
    let loc = Dune_sexp.Template.Pform.loc source in
    let variable =
      match Dune_pkg.Package_variable.of_macro_invocation ~loc invocation with
      | Ok variable -> variable
      | Error `Unexpected_macro -> Code_error.raise "Unexpected package variable macro" []
    in
    let* resolution = resolve_package_variable candidates candidate variable in
    (match resolution with
     | Resolved (Some value) -> dune_value value |> Result.ok |> Memo.return
     | Resolved None -> Memo.return (Error (`Undefined_pkg_var variable.name))
     | Requires_package_build ->
       unsupported := true;
       Memo.return (Ok [ Value.String "" ]))
  | _ ->
    unsupported := true;
    Memo.return (Ok [ Value.String "" ])
;;

let eval_source_condition candidates candidate solver_env condition =
  let unsupported = ref false in
  let expand sw =
    String_expander.Memo.expand_result_deferred_concat
      sw
      ~mode:Many
      ~f:(expand_condition_pform candidates candidate solver_env unsupported)
  in
  let+ enabled =
    Slang_expand.eval_blang
      condition
      ~dir:(Path.build (Candidate.artifact_root candidate))
      ~f:expand
  in
  if !unsupported then None else Some enabled
;;

let local_path path =
  String_with_vars.text_only path
  |> Option.map ~f:(Path.Local.parse_string_exn ~loc:(String_with_vars.loc path))
;;

(* The patches a recipe applies before doing anything else. Substitutions read
   package variables while they run, so a recipe containing one is left to its
   opaque build. *)
let leading_patches candidates candidate solver_env = function
  | None | Some Dune_pkg.Lock_dir.Build_command.Dune -> Memo.return ([], [], true)
  | Some (Action action) ->
    let rec loop patches actions =
      let stop () =
        let actions = List.map actions ~f:in_scope in
        Memo.return
          ( List.rev patches
          , actions
          , not (List.exists actions ~f:action_contains_source_transformation) )
      in
      match actions with
      | (_, Package_action.Patch path) :: rest ->
        (match local_path path with
         | Some patch -> loop ((String_with_vars.loc path, patch) :: patches) rest
         | None -> stop ())
      | (envs, Package_action.When (condition, action)) :: rest
        when action_contains_source_transformation action ->
        let condition = Slang.Blang.remove_locs condition |> Slang.simplify_blang in
        eval_source_condition candidates candidate solver_env condition
        >>= (function
         | None -> stop ()
         | Some true -> loop patches (flatten_progn envs action @ rest)
         | Some false -> loop patches rest)
      | _ -> stop ()
    in
    loop [] (flatten_progn [] action)
;;

module Scan_dune_files = Source_tree.Dir.Make_map_reduce (Memo) (Monoid.Exists)

let prepared_source context name =
  Path.Build.L.relative
    Private_context.t.build_dir
    [ Context_name.to_string context
    ; ".dune-source"
    ; Package.Name.to_string name
    ; "source"
    ]
;;

module Preparation = struct
  type t =
    | Opaque
    | Plain of
        { dir : Backing.t
        ; native : bool
        }
    | Prepared of
        { patches : (Loc.t * Path.Local.t) list
        ; rest : Package_action.t list
        ; native : bool
        }
end

let preparation_of_candidate candidates candidate =
  let* direct = Candidate.dependencies candidate in
  let candidates =
    Package.Name.Map.filteri candidates ~f:(fun name _ ->
      Package.Name.equal name (Candidate.name candidate)
      || Package.Name.Set.mem direct name)
  in
  let* platform = Lock_dir.Sys_vars.solver_env in
  let lock_pkg = Candidate.lock_pkg candidate in
  let build =
    Dune_pkg.Lock_dir.Conditional_choice.choose_for_platform
      lock_pkg.build_command
      ~platform
  in
  let* patches, rest, native = leading_patches candidates candidate platform build in
  let* has_files =
    Build_system.directory_target_contents_opt ~dir:(Candidate.files_dir candidate)
    >>| function
    | None -> false
    | Some (files, dirs) ->
      not (Filename.Array.Set.is_empty files && Filename.Array.Set.is_empty dirs)
  in
  if
    has_files
    || List.is_non_empty lock_pkg.info.extra_sources
    || List.is_non_empty patches
  then Memo.return (Preparation.Prepared { patches; rest; native })
  else
    let* root = Candidate.source_root candidate in
    match root with
    | None -> Memo.return Preparation.Opaque
    | Some dir ->
      let+ input = source candidate in
      if List.is_empty input.files then Preparation.Opaque else Plain { dir; native }
;;

let preparations =
  Per_context.create_by_name ~name:"package-source-preparations" (fun context ->
    Memo.lazy_ ~name:"package-source-preparations" (fun () ->
      let+ candidates = candidates context in
      Package.Name.Map.map candidates ~f:(fun candidate ->
        Memo.lazy_ ~name:"package-source-preparation" (fun () ->
          preparation_of_candidate candidates candidate)))
    |> Memo.Lazy.force)
  |> Staged.unstage
;;

let preparation context name =
  let* preparations = preparations context in
  match Package.Name.Map.find preparations name with
  | None -> Memo.return None
  | Some preparation -> Memo.Lazy.force preparation >>| Option.some
;;

let mount_backing context name =
  preparation context name
  >>| function
  | None | Some Opaque -> None
  | Some (Plain { dir; native = _ }) -> Some dir
  | Some (Prepared { patches = _; rest = _; native = _ }) ->
    Some (Backing.Build (prepared_source context name))
;;

let prepare context candidate =
  let name = Candidate.name candidate in
  Log.info
    "Prepare package sources"
    [ "context", Context_name.to_dyn context; "package", Package.Name.to_dyn name ];
  let* preparation = preparation context name >>| Option.value_exn in
  let* backing = mount_backing context name in
  match preparation, backing with
  | (Opaque | Plain { native = false; _ } | Prepared { native = false; _ }), _ | _, None
    -> Memo.return None
  | (Plain { native = true; _ } | Prepared { native = true; _ }), Some backing_root ->
    let logical_root = Candidate.artifact_root candidate in
    let* tree =
      Source_tree.load_mounted
        ~loc:(Candidate.source_loc candidate)
        ~logical_root
        ~backing_root
    in
    let* has_dune_file =
      Scan_dune_files.map_reduce
        tree
        ~traverse:Source_dir_status.Set.all
        ~trace_event_name:"Package source classification"
        ~f:(fun dir ->
          match Source_tree.Dir.dune_file dir with
          | None -> Memo.return false
          | Some _ ->
            let project = Source_tree.Dir.project dir in
            (match
               Package.Name.Map.find (Dune_project.including_hidden_packages project) name
             with
             | None -> Memo.return false
             | Some package -> Dune_load.package_enabled package))
    in
    Memo.return (Option.some_if has_dune_file tree)
;;

let mounted_by_name =
  Per_context.create_by_name ~name:"mounted-packages" (fun context ->
    Memo.lazy_ ~name:"mounted-packages" (fun () ->
      let+ candidates = candidates context in
      Package.Name.Map.map candidates ~f:(fun candidate ->
        Memo.lazy_ ~name:"prepare-mounted-package" (fun () ->
          let+ loaded = Memo.collect_user_errors (prepare context candidate) in
          { Mounted.candidate; loaded })))
    |> Memo.Lazy.force)
  |> Staged.unstage
;;

let find_mounted context name =
  let* mounted = mounted_by_name context in
  match Package.Name.Map.find mounted name with
  | None -> Memo.return None
  | Some mounted -> Memo.Lazy.force mounted >>| Option.some
;;

let find_mounted_kind context name =
  find_mounted context name
  >>= Memo.Option.map ~f:(fun mounted ->
    Mounted.kind_exn mounted >>| fun kind -> mounted, kind)
;;
