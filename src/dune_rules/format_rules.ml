open Import
open Memo.O

let add_diff loc alias ~input ~output =
  let open Action_builder.O in
  let dir = Alias.dir alias in
  let action =
    let dir = Path.Build.parent_exn dir in
    Action.Chdir (Path.build dir, Promote.Diff_action.diff input output)
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
  let package_name = Package.Name.of_string "ocamlformat"
  let exe_name = "ocamlformat"

  (** Resolve ocamlformat using the unified Tool_resolution system.
      Returns Some when the tool is configured via (tool) stanza, legacy dev tool,
      or has a lock directory. Returns None when it should be resolved from PATH. *)
  let resolve () = Tool_resolution.resolve_for_formatting ~package_name

  (* Config files for ocamlformat. When these are changed, running
     `dune fmt` should cause ocamlformat to re-format the ocaml files
     in the project. *)
  let config_files = [ ".ocamlformat"; ".ocamlformat-ignore"; ".ocamlformat-enable" ]

  let extra_deps dir =
    (* Set up the dependency on ocamlformat config files so changing
       these files triggers ocamlformat to run again. *)
    depend_on_files ~named:config_files (Path.build dir) |> Action_builder.with_no_targets
  ;;

  let flag_of_kind = function
    | Ml_kind.Impl -> "--impl"
    | Intf -> "--intf"
  ;;

  (** Action when ocamlformat is resolved (via stanza, legacy dev tool, or lock dir) *)
  let action_when_resolved ~(resolved : Tool_resolution.resolved) ~input ~output kind =
    let dir = Path.Build.parent_exn input in
    let action =
      (* An action which runs ocamlformat on the file at [input] and stores the
         resulting diff in the file at [output] *)
      Action_builder.with_stdout_to
        output
        (let open Action_builder.O in
         (* Use Tool_resolution to ensure the tool is built and get its environment *)
         let+ exe_path, env =
           Tool_resolution.with_tool_env resolved ~f:(fun ~exe_path ~env -> exe_path, env)
         (* Declare the dependency on the input file so changes to the input
            file trigger ocamlformat to run again on the updated file. *)
         and+ () = Action_builder.path (Path.build input) in
         let args = [ flag_of_kind kind; Path.Build.basename input ] in
         Action.chdir (Path.build dir) @@ Action.run (Ok exe_path) args
         |> Action.Full.make
         |> Action.Full.add_env env)
    in
    let open Action_builder.With_targets.O in
    (* Depend on [extra_deps] so if the ocamlformat config file
       changes then ocamlformat will run again. *)
    extra_deps dir
    >>> action
    |> With_targets.map ~f:(Action.Full.add_sandbox Sandbox_config.needs_sandboxing)
  ;;

  (** Action when ocamlformat is not resolved (use system PATH) *)
  let action_when_not_resolved ~input kind =
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

let format_action format ~ocamlformat_resolved ~input ~output ~expander kind =
  match (format : Dialect.Format.t) with
  | Ocamlformat ->
    (match ocamlformat_resolved with
     | Some (resolved, _source) ->
       (* Tool is configured via stanza, legacy dev tool, or lock dir *)
       Memo.return (Ocamlformat.action_when_resolved ~resolved ~input ~output kind)
     | None ->
       (* Fall back to system PATH *)
       let loc = Loc.none in
       let action, extra_deps = Ocamlformat.action_when_not_resolved ~input kind in
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
  (* Use unified Tool_resolution to check if ocamlformat is configured *)
  let* ocamlformat_resolved = Ocamlformat.resolve () in
  let setup_formatting file =
    (let input_basename = Path.Source.basename file in
     let input = Path.Build.relative dir input_basename in
     let output = Path.Build.relative output_dir input_basename in
     let open Option.O in
     let* dialect, kind =
       Path.Source.extension file |> Dialect.DB.find_by_extension dialects
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
     format_action format ~ocamlformat_resolved ~input ~output ~expander kind
     |> Memo.bind ~f:(fun rule ->
       match ocamlformat_resolved with
       | Some _ ->
         (* Tool is resolved - environment is already included in the action *)
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
