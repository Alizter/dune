open Import
open Memo.O
module Gen_rules = Build_config.Gen_rules

let root_dir_basename = ".lockfile"
let artifact_dir_basename = "pkg"

let package_of_artifact_path path =
  match Path.Build.extract_build_context path with
  | None -> None
  | Some (_, source) ->
    (match Path.Source.explode source |> Filename.L.to_string with
     | root :: packages :: name :: _
       when String.equal root root_dir_basename
            && String.equal packages artifact_dir_basename ->
       Package.Name.of_string_opt name
     | _ -> None)
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
