open Import

let deps_of ~sandbox ~modules ~sctx ~dir ~ml_kind ~for_:_ unit =
  let source = Option.value_exn (Module.source unit ~ml_kind) in
  let context = Super_context.context sctx in
  let action =
    let open Action_builder.O in
    let* codept_prog = Super_context.resolve_program sctx ~dir ~loc:None "codept" in
    let flags, sandbox =
      Module.pp_flags unit |> Option.value ~default:(Action_builder.return [], sandbox)
    in
    let+ action =
      Command.run'
        ~sandbox
        ~dir:(Path.build (Context.build_dir context))
        codept_prog
        [ A "-m2l"
        ; Command.Args.dyn flags
        ; Command.Ml_kind.flag ml_kind
        ; Dep (Module.File.path source)
        ]
    in
    { Rule.Anonymous_action.action; loc = Loc.none; dir; alias = None }
  in
  Dune_engine.Build_system.execute_action_stdout action
  |> Memo.map ~f:(fun output ->
    let sexps = Dune_sexp.Parser.parse_string ~fname:"codept" ~mode:Many output in
    let m2l = Codept_m2l.of_sexp sexps in
    let unit_names = Codept_m2l.compilation_units m2l in
    let deps =
      List.concat_map unit_names ~f:(fun name ->
        let m = Module_name.of_checked_string name in
        match Modules.With_vlib.find_dep modules ~of_:unit m with
        | Ok s -> s
        | Error `Parent_cycle -> [])
    in
    Stdlib.( @ ) (Modules.With_vlib.implicit_deps modules ~of_:unit) deps)
  |> Action_builder.of_memo
;;
