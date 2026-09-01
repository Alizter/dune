open Import
open Memo.O
module Gen_rules = Build_config.Gen_rules
module Lock_pkg = Dune_pkg.Lock_dir.Pkg

let artifact_dir_basename = "pkg"

module Candidate = struct
  type t =
    { lock_pkg : Lock_pkg.t
    ; source_root : Path.Build.t option
    ; files_dir : Path.Build.t
    ; artifact_root : Path.Build.t
    }

  let name t = t.lock_pkg.info.name
  let source_root t = t.source_root
  let lock_pkg t = t.lock_pkg
  let files_dir t = t.files_dir
  let artifact_root t = t.artifact_root

  let make context (lock_pkg : Lock_pkg.t) ~files_dir =
    let mounted_context = Context_name.build_dir (Mounted_context.make context) in
    let source_root =
      Option.map lock_pkg.info.source ~f:(fun source ->
        Fetch_rules.target source `Directory)
    in
    let artifact_root =
      Path.Build.L.relative
        mounted_context
        [ artifact_dir_basename; Package.Name.to_string lock_pkg.info.name ]
    in
    { lock_pkg; source_root; files_dir; artifact_root }
  ;;
end

module Mounted = struct
  type source_kind =
    | Primary_source
    | No_source

  type kind =
    | Dune
    | Opam of Opam_stanza.t

  type t =
    { candidate : Candidate.t
    ; source_root : Path.Build.t
    ; projects : (Dune_project.t * Source_tree.Rules.Dir.t) list
    ; tree : Source_tree.Rules.Mounted.t option
    ; source_kind : source_kind
    ; kind : kind
    ; package : Package.t
    }

  let candidate t = t.candidate
  let working_dir t = t.source_root
  let projects t = t.projects
  let tree t = t.tree
  let source_kind t = t.source_kind
  let kind t = t.kind
  let package t = t.package

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
    and* lock_dir_path = Lock_dir.get_path context >>| Option.value_exn
    and* platform = Lock_dir.Sys_vars.solver_env in
    Dune_pkg.Lock_dir.packages_on_platform lock_dir ~platform
    |> Package.Name.Map.values
    |> List.map ~f:(fun (lock_pkg : Lock_pkg.t) ->
      let version =
        Option.some_if
          (Dune_pkg.Lock_dir.uses_versioned_paths lock_dir)
          lock_pkg.info.version
      in
      let files_dir =
        Dune_pkg.Lock_dir.Pkg.files_dir lock_pkg.info.name version ~lock_dir:lock_dir_path
        |> Path.as_in_build_dir_exn
      in
      Candidate.make context lock_pkg ~files_dir)
    |> Memo.return
;;

let candidates =
  Per_context.create_by_name ~name:"mounted-package-candidates" load_candidates
  |> Staged.unstage
;;

let find_candidate context name =
  let+ candidates = candidates context in
  List.find candidates ~f:(fun candidate ->
    Package.Name.equal name (Candidate.name candidate))
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

module Mounted_source_tree = Source_tree.Rules.Mounted
module Source_substs = Dune_pkg.Substs.Make (Memo)
module Package_action = Dune_lang.Action

type source_transformation =
  | Substitute of String_with_vars.t * String_with_vars.t
  | Patch of String_with_vars.t

type 'a transformation_result =
  | Supported of 'a
  | Unsupported

type variable_resolution =
  | Resolved of OpamVariable.variable_contents option
  | Requires_package_build

let find_candidate_in candidates name =
  List.find candidates ~f:(fun candidate ->
    Package.Name.equal (Candidate.name candidate) name)
;;

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
  match find_candidate_in candidates package with
  | None ->
    let value =
      match Dune_lang.Package_variable_name.to_string name with
      | "installed" -> Some (OpamVariable.B false)
      | "enable" -> Some (S "disable")
      | "pinned" -> Some (B false)
      | _ -> None
    in
    Resolved value
  | Some package ->
    let variables =
      Dune_pkg.Lock_dir.Pkg_info.variables package.Candidate.lock_pkg.info
    in
    (match Dune_lang.Package_variable_name.Map.find variables name with
     | Some value -> Resolved (Some value)
     | None ->
       (match Dune_lang.Package_variable_name.to_string name with
        | "installed" -> Resolved (Some (B true))
        | "enable" -> Resolved (Some (S "enable"))
        | "pinned" -> Resolved (Some (B false))
        | "build-id" -> Resolved (Some (S "d00ed00ed00ed00ed00ed00ed00ed00e"))
        | _ -> Requires_package_build))
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

let rec flatten_progn = function
  | Package_action.Progn actions -> List.concat_map actions ~f:flatten_progn
  | Withenv (_, action) -> flatten_progn action
  | action -> [ action ]
;;

let values_of_variable = function
  | OpamVariable.B value -> [ Value.String (Bool.to_string value) ]
  | S value -> [ Value.String value ]
  | L values -> List.map values ~f:(fun value -> Value.String value)
;;

let solver_variable solver_env name =
  Dune_pkg.Solver_env.get solver_env name
  |> Option.map ~f:Dune_pkg.Variable_value.to_opam_variable_contents
;;

let solver_values solver_env name =
  solver_variable solver_env name
  |> Option.map ~f:values_of_variable
  |> Option.value ~default:[ Value.String "" ]
;;

let resolve_global_variable solver_env name =
  match Dune_lang.Package_variable_name.to_string name with
  | "switch" -> Resolved (Some (OpamVariable.S "dune"))
  | "jobs" -> Resolved (Some (S (Int.to_string !Clflags.concurrency)))
  | "user" -> Resolved (Some (S (Unix.getlogin ())))
  | "group" ->
    let group = Unix.getgid () |> Unix.getgrgid in
    Resolved (Some (S group.gr_name))
  | "build"
  | "prefix"
  | "lib"
  | "libexec"
  | "bin"
  | "sbin"
  | "toplevel"
  | "share"
  | "etc"
  | "doc"
  | "stublibs"
  | "man" -> Requires_package_build
  | _ ->
    (match solver_variable solver_env name with
     | Some value -> Resolved (Some value)
     | None -> Requires_package_build)
;;

let expand_context_variable solver_env unsupported (variable : Pform.Var.Pkg.t) =
  let open Pform.Var.Pkg in
  match variable with
  | Switch -> [ Value.String "dune" ]
  | Os Pform.Var.Os.Os -> solver_values solver_env Dune_lang.Package_variable_name.os
  | Os Os_version -> solver_values solver_env Dune_lang.Package_variable_name.os_version
  | Os Os_distribution ->
    solver_values solver_env Dune_lang.Package_variable_name.os_distribution
  | Os Os_family -> solver_values solver_env Dune_lang.Package_variable_name.os_family
  | Arch -> solver_values solver_env Dune_lang.Package_variable_name.arch
  | Sys_ocaml_version ->
    solver_values solver_env Dune_lang.Package_variable_name.sys_ocaml_version
  | Jobs -> [ Value.String (Int.to_string !Clflags.concurrency) ]
  | User -> [ Value.String (Unix.getlogin ()) ]
  | Group ->
    let group = Unix.getgid () |> Unix.getgrgid in
    [ Value.String group.gr_name ]
  | Build | Prefix | Section_dir _ ->
    unsupported := true;
    [ Value.String "" ]
;;

let expand_condition_pform candidates candidate solver_env unsupported ~source = function
  | Pform.Var (Pkg variable) ->
    expand_context_variable solver_env unsupported variable |> Result.ok |> Memo.return
  | Macro ({ macro = Pkg | Pkg_self; _ } as invocation) ->
    let loc = Dune_sexp.Template.Pform.loc source in
    let variable =
      match Dune_pkg.Package_variable.of_macro_invocation ~loc invocation with
      | Ok variable -> variable
      | Error `Unexpected_macro -> Code_error.raise "Unexpected package variable macro" []
    in
    (match resolve_package_variable candidates candidate variable with
     | Resolved (Some value) -> values_of_variable value |> Result.ok |> Memo.return
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

let source_transformations candidates candidate solver_env = function
  | None | Some Dune_pkg.Lock_dir.Build_command.Dune -> Memo.return (Supported [])
  | Some (Action action) ->
    let rec loop transformations = function
      | Package_action.Substitute (source, target) :: actions ->
        (match String_with_vars.text_only source, String_with_vars.text_only target with
         | Some _, Some _ -> loop (Substitute (source, target) :: transformations) actions
         | None, _ | _, None -> Memo.return Unsupported)
      | Patch path :: actions ->
        (match String_with_vars.text_only path with
         | Some _ -> loop (Patch path :: transformations) actions
         | None -> Memo.return Unsupported)
      | Package_action.When (condition, action) :: actions
        when action_contains_source_transformation action ->
        let condition = Slang.Blang.remove_locs condition |> Slang.simplify_blang in
        eval_source_condition candidates candidate solver_env condition
        >>= (function
         | None -> Memo.return Unsupported
         | Some true -> loop transformations (flatten_progn action @ actions)
         | Some false -> loop transformations actions)
      | action :: actions ->
        if
          action_contains_source_transformation action
          || List.exists actions ~f:action_contains_source_transformation
        then Memo.return Unsupported
        else Memo.return (Supported (List.rev transformations))
      | [] -> Memo.return (Supported (List.rev transformations))
    in
    loop [] (flatten_progn action)
;;

let local_path path =
  String_with_vars.text_only path
  |> Option.map ~f:(Path.Local.parse_string_exn ~loc:(String_with_vars.loc path))
;;

let logical_path candidate path =
  Path.Build.append_local (Candidate.artifact_root candidate) path
;;

let read_source_file candidate layers path =
  Mounted_source_tree.read_file ~logical:(logical_path candidate path) ~layers
;;

let merge_dependencies contents =
  List.concat_map contents ~f:(fun { Source_tree.Rules.File.dependencies; _ } ->
    dependencies)
  |> Path.Set.of_list
  |> Path.Set.to_list
;;

let apply_patch candidate layers path =
  let loc = String_with_vars.loc path in
  let path = Option.value_exn (local_path path) in
  let logical = logical_path candidate path in
  let* patch_contents = read_source_file candidate layers path in
  let patch_contents =
    match patch_contents with
    | Some contents -> contents
    | None ->
      User_error.raise
        ~loc
        [ Pp.textf "Patch file %S does not exist" (Path.Local.to_string path) ]
  in
  let patches =
    Dune_patch.File_patch.parse
      ~loc
      ~patch_file:(Path.build logical)
      patch_contents.contents
  in
  Memo.List.fold_left patches ~init:layers ~f:(fun layers patch ->
    let source = Dune_patch.File_patch.source patch in
    let target = Dune_patch.File_patch.target patch in
    let* source_contents =
      match source with
      | None -> Memo.return None
      | Some source -> read_source_file candidate layers source
    in
    let* target_contents =
      match target with
      | None -> Memo.return None
      | Some target -> read_source_file candidate layers target
    in
    let dependencies =
      merge_dependencies
        (patch_contents :: List.filter_opt [ source_contents; target_contents ])
    in
    let contents =
      Dune_patch.File_patch.apply
        patch
        (Option.map source_contents ~f:(fun { contents; _ } -> contents))
    in
    let executable =
      let contents =
        if Dune_patch.File_patch.preserves_source_mode patch
        then source_contents
        else target_contents
      in
      match contents with
      | None -> false
      | Some { executable; _ } -> executable
    in
    let layers =
      match source with
      | Some source when Dune_patch.File_patch.removes_source patch ->
        layers
        @ [ Mounted_source_tree.Layer.delete ~logical:(logical_path candidate source) ]
      | Some _ | None -> layers
    in
    let layers =
      match target, contents with
      | Some target, Some contents ->
        layers
        @ [ Mounted_source_tree.Layer.contents
              ~logical:(logical_path candidate target)
              ~contents
              ~executable
              ~dependencies
          ]
      | Some target, None ->
        layers
        @ [ Mounted_source_tree.Layer.delete ~logical:(logical_path candidate target) ]
      | None, None -> layers
      | None, Some _ ->
        Code_error.raise
          "Patch produced contents without a target"
          [ "patch", Dune_patch.File_patch.to_dyn patch ]
    in
    Memo.return layers)
;;

let substitution_env candidates candidate solver_env unsupported = function
  | Dune_pkg.Substs.Variable.Global name ->
    (match resolve_global_variable solver_env name with
     | Resolved value -> Memo.return value
     | Requires_package_build ->
       unsupported := true;
       Memo.return None)
  | Package variable ->
    (match resolve_package_variable candidates candidate variable with
     | Resolved value -> Memo.return value
     | Requires_package_build ->
       unsupported := true;
       Memo.return None)
;;

let apply_substitution candidates candidate solver_env layers source target =
  let loc = String_with_vars.loc source in
  let source = Option.value_exn (local_path source) in
  let target = Option.value_exn (local_path target) in
  let* source_contents = read_source_file candidate layers source in
  let source_contents =
    match source_contents with
    | Some contents -> contents
    | None ->
      User_error.raise
        ~loc
        [ Pp.textf "Substitution input %S does not exist" (Path.Local.to_string source) ]
  in
  let* target_contents = read_source_file candidate layers target in
  let executable =
    match target_contents with
    | None -> false
    | Some { executable; _ } -> executable
  in
  let dependencies =
    merge_dependencies (source_contents :: Option.to_list target_contents)
  in
  let unsupported = ref false in
  let+ contents =
    Source_substs.subst_contents
      (substitution_env candidates candidate solver_env unsupported)
      (Candidate.name candidate)
      ~src:(Path.build (logical_path candidate source))
      source_contents.contents
  in
  if !unsupported
  then Unsupported
  else
    Supported
      (layers
       @ [ Mounted_source_tree.Layer.contents
             ~logical:(logical_path candidate target)
             ~contents
             ~executable
             ~dependencies
         ])
;;

let apply_source_transformations candidates candidate solver_env layers transformations =
  let rec loop layers = function
    | [] -> Memo.return (Supported layers)
    | Substitute (source, target) :: transformations ->
      apply_substitution candidates candidate solver_env layers source target
      >>= (function
       | Unsupported -> Memo.return Unsupported
       | Supported layers -> loop layers transformations)
    | Patch path :: transformations ->
      let* layers = apply_patch candidate layers path in
      loop layers transformations
  in
  loop layers transformations
;;

let load_source candidates candidate backing_root =
  let logical_root = Candidate.artifact_root candidate in
  let layers =
    Mounted_source_tree.Layer.directory ~logical_root ~backing_root
    :: Mounted_source_tree.Layer.directory
         ~logical_root
         ~backing_root:(Candidate.files_dir candidate)
    :: List.map
         (Candidate.lock_pkg candidate).info.extra_sources
         ~f:(fun (local, source) ->
           Mounted_source_tree.Layer.file
             ~logical:(Path.Build.append_local logical_root local)
             ~backing:(Fetch_rules.target source `File))
  in
  let* build, _, _ = selected_recipe candidate in
  let* solver_env = Lock_dir.Sys_vars.solver_env in
  let* transformations = source_transformations candidates candidate solver_env build in
  match transformations with
  | Unsupported -> Memo.return None
  | Supported transformations ->
    apply_source_transformations candidates candidate solver_env layers transformations
    >>= (function
     | Unsupported -> Memo.return None
     | Supported layers -> Mounted_source_tree.load ~logical_root ~layers >>| Option.some)
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

let mount candidate source_root tree dependencies =
  let projects = Mounted_source_tree.projects tree in
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
        , source_dir ))
    in
    let package =
      make_package candidate (Candidate.artifact_root candidate) dependencies
    in
    Memo.return
      (Some
         { Mounted.candidate
         ; source_root
         ; projects
         ; tree = Some tree
         ; source_kind = Primary_source
         ; kind = Dune
         ; package
         }))
;;

module Scan_dune_files = Source_tree.Rules.Dir.Make_map_reduce (Memo) (Monoid.Exists)

let has_dune_file tree =
  Scan_dune_files.map_reduce
    (Mounted_source_tree.root tree)
    ~traverse:Source_dir_status.Set.all
    ~trace_event_name:"Package source classification"
    ~f:(fun dir -> Memo.return (Option.is_some (Source_tree.Rules.Dir.dune_file dir)))
;;

let make_opam candidate ~source_root ~source_kind =
  let* build, install, dependencies = selected_recipe candidate in
  let package = make_package candidate source_root dependencies in
  let stanza =
    { Opam_stanza.loc = Loc.none
    ; origin = Lock
    ; package
    ; build
    ; install
    ; depexts = candidate.lock_pkg.depexts
    ; exported_env = candidate.lock_pkg.exported_env
    }
  in
  { Mounted.candidate
  ; source_root
  ; projects = []
  ; tree = None
  ; source_kind
  ; kind = Opam stanza
  ; package
  }
  |> Memo.return
;;

let prepare candidates candidate =
  match Candidate.source_root candidate with
  | Some source_root ->
    let make_opaque_opam () =
      make_opam candidate ~source_root ~source_kind:Primary_source >>| Option.some
    in
    let* tree = load_source candidates candidate source_root in
    (match tree with
     | None -> make_opaque_opam ()
     | Some tree ->
       let* has_dune_file = has_dune_file tree in
       if has_dune_file
       then
         let* _, _, dependencies = selected_recipe candidate in
         mount candidate source_root tree dependencies
         >>= function
         | Some mounted -> Memo.return (Some mounted)
         | None -> make_opaque_opam ()
       else make_opaque_opam ())
  | None ->
    let source_root =
      Path.Build.L.relative
        (Candidate.artifact_root candidate)
        [ ".opam"; Candidate.name candidate |> Package.Name.to_string; "source" ]
    in
    make_opam candidate ~source_root ~source_kind:No_source >>| Option.some
;;

let load_mounted context =
  let start = Time.now () in
  let* candidates = candidates context in
  let+ mounted =
    Memo.parallel_map candidates ~f:(prepare candidates) >>| List.filter_opt
  in
  Dune_trace.emit Pkg (fun () ->
    Dune_trace.Event.mounted_packages_load
      ~start
      ~stop:(Time.now ())
      ~context:(Context_name.to_string context)
      ~mounted:(List.length mounted));
  mounted
;;

let selected_package_names context =
  let+ candidates = candidates context in
  List.map candidates ~f:Candidate.name |> Package.Name.Set.of_list
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
  let file = Source_tree.Rules.Dir.file source_dir filename in
  let* materialization = Source_tree.Rules.File.materialization file in
  let dst = Path.Build.relative_fname dir filename in
  match materialization with
  | None ->
    Code_error.raise
      "Mounted source file selected without materialization"
      [ "file", Source_tree.Rules.File.source_path file |> Source_path.to_dyn ]
  | Some (Copy src) ->
    let { Action_builder.With_targets.build; targets } = Action_builder.copy ~src ~dst in
    Rule.make ~info:(Rule.Info.Source_file_copy src) ~targets build |> Memo.return
  | Some (Write { contents; executable; dependencies }) ->
    let perm =
      if executable
      then Dune_lang.Action.File_perm.Executable
      else Dune_lang.Action.File_perm.Normal
    in
    let { Action_builder.With_targets.build; targets } =
      Action_builder.write_file ~perm dst contents
    in
    let build =
      let open Action_builder.O in
      let* () = Action_builder.paths dependencies in
      build
    in
    let source = Source_tree.Rules.File.path file in
    Rule.make ~info:(Rule.Info.Source_file_copy source) ~targets build |> Memo.return
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
      let* source_rules =
        Filename.Array.Set.to_list selected.source_filenames
        |> Memo.List.map ~f:(fun filename -> source_copy_rule ~dir ~source_dir filename)
      in
      Memo.return (Rules.union (Rules.of_rules source_rules) generated_rules)
    in
    { generated with rules })
;;
