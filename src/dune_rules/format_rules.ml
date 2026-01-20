open Import
open Memo.O

let add_diff loc alias ~input ~output =
  let open Action_builder.O in
  let dir = Alias.dir alias in
  let action =
    let dir = Path.Build.parent_exn dir in
    Action.Chdir (Path.build dir, Action.diff input output)
  in
  Action_builder.paths [ input; Path.build output ]
  >>> Action_builder.return (Action.Full.make action)
  |> Rules.Produce.Alias.add_action alias ~loc
;;

let rec subdirs_until_root dir =
  match Path.parent dir with
  | None -> [ dir ]
  | Some d -> dir :: subdirs_until_root d
;;

let depend_on_files ~named dir =
  subdirs_until_root dir
  |> List.concat_map ~f:(fun dir -> List.map named ~f:(Path.relative dir))
  |> Action_builder.paths_existing
;;

let formatted_dir_basename = ".formatted"

module Alias = struct
  let fmt ~dir = Alias.make Alias0.fmt ~dir
end

module Ocamlformat = struct
  let exe_name = "ocamlformat"
  let package_name = Package.Name.of_string "ocamlformat"

  (* Config files for ocamlformat. When these are changed, running
     `dune fmt` should cause ocamlformat to re-format the ocaml files
     in the project. *)
  let config_files = [ ".ocamlformat"; ".ocamlformat-ignore"; ".ocamlformat-enable" ]

  let extra_deps dir =
    depend_on_files ~named:config_files (Path.build dir) |> Action_builder.with_no_targets
  ;;

  let flag_of_kind = function
    | Ml_kind.Impl -> "--impl"
    | Intf -> "--intf"
  ;;

  (** Check if the required version is locked.
      Returns Some version if locked, None otherwise. *)
  let find_locked_version ~source_dir =
    match Dune_pkg.Ocamlformat.version_for_dir source_dir with
    | None ->
      (* No version specified in .ocamlformat - use system PATH *)
      Memo.return None
    | Some required_version ->
      (* Check if this version is locked *)
      let+ versions = Tool_lock.get_locked_versions package_name in
      List.find_map versions ~f:(fun (v, _path) ->
        if Package_version.equal v required_version then Some v else None)
  ;;

  (** Action when ocamlformat is locked - use Pkg_rules.tool_exe_path *)
  let action_when_locked ~version ~input ~output kind =
    let dir = Path.Build.parent_exn input in
    let action =
      Action_builder.with_stdout_to
        output
        (let open Action_builder.O in
         let+ exe_path =
           Pkg_rules.tool_exe_path ~package_name ~version ~executable:exe_name
         and+ () = Action_builder.path (Path.build input) in
         let args = [ flag_of_kind kind; Path.Build.basename input ] in
         let bin_dir = Path.parent_exn exe_path in
         let env = Env_path.cons Env.empty ~dir:bin_dir in
         Action.chdir (Path.build dir) @@ Action.run (Ok exe_path) args
         |> Action.Full.make
         |> Action.Full.add_env env)
    in
    let open Action_builder.With_targets.O in
    extra_deps dir
    >>> action
    |> With_targets.map ~f:(Action.Full.add_sandbox Sandbox_config.needs_sandboxing)
  ;;

  (** Action when ocamlformat is not locked (use system PATH) *)
  let action_when_not_locked ~input kind =
    let module S = String_with_vars in
    let dir = Path.Build.parent_exn input in
    ( Dune_lang.Action.chdir
        (S.make_pform Loc.none (Var Workspace_root))
        (Dune_lang.Action.run
           (S.make_text Loc.none exe_name)
           [ S.make_text Loc.none (flag_of_kind kind)
           ; S.make_pform Loc.none (Var Input_file)
           ])
    , extra_deps dir )
  ;;
end

let format_action format ~ocamlformat_version ~input ~output ~expander kind =
  match (format : Dialect.Format.t) with
  | Ocamlformat ->
    (match ocamlformat_version with
     | Some version ->
       (* Tool is locked - use Pkg_rules.tool_exe_path *)
       Memo.return (Ocamlformat.action_when_locked ~version ~input ~output kind)
     | None ->
       (* Fall back to system PATH *)
       let loc = Loc.none in
       let action, extra_deps = Ocamlformat.action_when_not_locked ~input kind in
       let+ expander = expander in
       let open Action_builder.With_targets.O in
       extra_deps
       >>> Pp_spec_rules.action_for_pp_with_target
             ~sandbox:Sandbox_config.default
             ~loc
             ~expander
             ~action
             ~src:input
             ~target:output)
  | Action (loc, action) ->
    let+ expander = expander in
    let open Action_builder.With_targets.O in
    Action_builder.With_targets.return ()
    >>> Pp_spec_rules.action_for_pp_with_target
          ~sandbox:Sandbox_config.default
          ~loc
          ~expander
          ~action
          ~src:input
          ~target:output
;;

let gen_rules_output
      sctx
      (config : Format_config.t)
      ~version
      ~dialects
      ~expander
      ~output_dir
  =
  assert (formatted_dir_basename = Path.Build.basename output_dir);
  let loc = Format_config.loc config in
  let dir = Path.Build.parent_exn output_dir in
  let alias_formatted = Alias.fmt ~dir:output_dir in
  let source_dir_path = Path.Build.drop_build_context_exn dir in
  (* Check if ocamlformat is locked for this directory *)
  let* ocamlformat_version =
    Ocamlformat.find_locked_version ~source_dir:source_dir_path
  in
  let setup_formatting file =
    (let input_basename = Path.Source.basename file in
     let input = Path.Build.relative dir input_basename in
     let output = Path.Build.relative output_dir input_basename in
     let open Option.O in
     let* dialect, kind =
       Path.Source.extension file
       |> Filename.Extension.Or_empty.extension
       |> Option.bind ~f:(Dialect.DB.find_by_extension dialects)
     in
     let* () =
       Option.some_if (Format_config.includes config (Dialect (Dialect.name dialect))) ()
     in
     let+ format =
       match Dialect.format dialect kind with
       | Some _ as action -> action
       | None ->
         (match Dialect.preprocess dialect kind with
          | None -> Dialect.format Dialect.ocaml kind
          | Some _ -> None)
     in
     format_action format ~ocamlformat_version ~input ~output ~expander kind
     |> Memo.bind ~f:(fun rule ->
       match ocamlformat_version with
       | Some _ ->
         (* Tool is locked - rule is self-contained *)
         let { Action_builder.With_targets.build; targets } = rule in
         Rule.make ~mode:Standard ~targets build |> Rules.Produce.rule
       | None ->
         (* Fall back to system PATH - use Super_context for rule generation *)
         let open Memo.O in
         let* sctx = sctx in
         Super_context.add_rule sctx ~mode:Standard ~loc ~dir rule)
     >>> add_diff loc alias_formatted ~input:(Path.build input) ~output)
    |> Memo.Option.iter ~f:Fun.id
  in
  let* source_dir = Source_tree.find_dir (Path.Build.drop_build_context_exn dir) in
  let* () =
    Memo.Option.iter source_dir ~f:(fun source_dir ->
      Source_tree.Dir.filenames source_dir
      |> Filename.Set.to_seq
      |> Memo.parallel_iter_seq ~f:(fun file ->
        Path.Source.relative (Source_tree.Dir.path source_dir) file |> setup_formatting))
  and* () =
    match Format_config.includes config Dune with
    | false -> Memo.return ()
    | true ->
      Memo.Option.iter source_dir ~f:(fun source_dir ->
        Source_tree.Dir.dune_file source_dir
        |> Memo.Option.iter ~f:(fun f ->
          Source.Dune_file.path f
          |> Memo.Option.iter ~f:(fun path ->
            let input_basename = Path.Source.basename path in
            let input = Path.build (Path.Build.relative dir input_basename) in
            let output = Path.Build.relative output_dir input_basename in
            let { Action_builder.With_targets.build; targets } =
              (let open Action_builder.O in
               let+ () = Action_builder.path input in
               Action.Full.make (Format_dune_file.action ~version input output))
              |> Action_builder.with_file_targets ~file_targets:[ output ]
            in
            let rule = Rule.make ~mode:Standard ~targets build in
            Rules.Produce.rule rule >>> add_diff loc alias_formatted ~input ~output)))
  in
  Rules.Produce.Alias.add_deps alias_formatted (Action_builder.return ())
;;

let format_config ~dir =
  let+ value =
    Env_stanza_db.value_opt ~dir ~f:(fun (t : Dune_env.config) ->
      Memo.return t.format_config)
  and+ default =
    (* we always force the default for error checking *)
    Path.Build.drop_build_context_exn dir
    |> Source_tree.nearest_dir
    >>| Source_tree.Dir.project
    >>| Dune_project.format_config
  in
  Option.value value ~default
;;

let with_config ~dir f =
  let* config = format_config ~dir in
  if Format_config.is_empty config
  then
    (* CR-someday rgrinberg: this [is_empty] check is weird. We should use [None]
       to represent that no settings have been set. *)
    Memo.return ()
  else f config
;;

let gen_rules sctx ~output_dir =
  let dir = Path.Build.parent_exn output_dir in
  with_config ~dir (fun config ->
    let expander = sctx >>= Super_context.expander ~dir in
    let* project = Dune_load.find_project ~dir in
    let dialects = Dune_project.dialects project in
    let version = Dune_project.dune_version project in
    gen_rules_output sctx config ~version ~dialects ~expander ~output_dir)
;;

let setup_alias ~dir =
  with_config ~dir (fun (_ : Format_config.t) ->
    let output_dir = Path.Build.relative dir formatted_dir_basename in
    let alias = Alias.fmt ~dir in
    let alias_formatted = Alias.fmt ~dir:output_dir in
    Rules.Produce.Alias.add_deps alias (Action_builder.dep (Dep.alias alias_formatted)))
;;
