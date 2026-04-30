open Import

let parse_deps_exn ~file lines =
  let invalid () =
    User_error.raise
      [ Pp.textf
          "codept returned unexpected output for %s:"
          (Path.to_string_maybe_quoted file)
      ; Pp.vbox
          (Pp.concat_map lines ~sep:Pp.cut ~f:(fun line ->
             Pp.seq (Pp.verbatim "> ") (Pp.verbatim line)))
      ]
  in
  match lines with
  | [] | _ :: _ :: _ -> invalid ()
  | [ line ] ->
    (match String.lsplit2 line ~on:':' with
     | None -> invalid ()
     | Some (basename, deps) ->
       let basename = Filename.basename basename in
       if basename <> Path.basename file then invalid ();
       String.extract_blank_separated_words deps)
;;

let parse_module_names ~dir ~(unit : Module.t) ~modules words =
  List.concat_map words ~f:(fun m ->
    let m = Module_name.of_checked_string m in
    match Modules.With_vlib.find_dep modules ~of_:unit m with
    | Ok s -> s
    | Error `Parent_cycle ->
      User_error.raise
        [ Pp.textf
            "Module %s in directory %s depends on %s."
            (Module_name.to_string (Module.name unit))
            (Path.to_string_maybe_quoted (Path.build dir))
            (Module_name.to_string m)
        ; Pp.textf "This doesn't make sense to me."
        ; Pp.nop
        ; Pp.textf
            "%s is the main module of the library and is the only module exposed outside \
             of the library. Consequently, it should be the one depending on all the other \
             modules in the library."
            (Module_name.to_string m)
        ])
;;

let deps_of ~sandbox ~modules ~sctx ~dir ~ml_kind ~for_:_ unit =
  let source = Option.value_exn (Module.source unit ~ml_kind) in
  let context = Super_context.context sctx in
  let action =
    let open Action_builder.O in
    let* codept_prog =
      Super_context.resolve_program sctx ~dir ~loc:None "codept"
    in
    let flags, sandbox =
      Module.pp_flags unit
      |> Option.value ~default:(Action_builder.return [], sandbox)
    in
    let+ action =
      Command.run' ~sandbox
        ~dir:(Path.build (Context.build_dir context))
        codept_prog
        [ A "-modules"
        ; Command.Args.dyn flags
        ; Command.Ml_kind.flag ml_kind
        ; Dep (Module.File.path source)
        ]
    in
    { Rule.Anonymous_action.action; loc = Loc.none; dir; alias = None }
  in
  Dune_engine.Build_system.execute_action_stdout action
  |> Memo.map ~f:(fun output ->
    let words =
      parse_deps_exn ~file:(Module.File.path source) (String.split_lines output)
    in
    let deps = parse_module_names ~dir ~unit ~modules words in
    Stdlib.( @ ) (Modules.With_vlib.implicit_deps modules ~of_:unit) deps)
  |> Action_builder.of_memo
;;
