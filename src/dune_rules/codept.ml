open Import

let resolve_in_libs ~libs ~for_ name =
  List.find_map libs ~f:(fun lib ->
    let info = Lib.info lib in
    let obj_dir = Lib_info.obj_dir info in
    match Lib_info.modules info ~for_ with
    | External (Some modules) ->
      (match Modules.With_vlib.find modules name with
       | Some module_ -> Obj_dir.Module.cm_file obj_dir module_ ~kind:(Ocaml Cmi)
       | None -> None)
    | External None | Local -> None)
;;

let run_codept ~sctx ~dir ~sandbox ~ml_kind unit =
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
    Codept_m2l.compilation_units m2l)
;;

let cm_deps (cctx : Compilation_context.t) ~ml_kind ~cm_kind m =
  let sctx = Compilation_context.super_context cctx in
  let obj_dir = Compilation_context.obj_dir cctx in
  let modules = Compilation_context.modules cctx in
  let for_ = Compilation_context.for_ cctx in
  let sandbox = Compilation_context.sandbox cctx in
  let dir = Obj_dir.dir obj_dir in
  let opaque = Compilation_context.opaque cctx in
  let requires_compile = Compilation_context.requires_compile cctx in
  let open Action_builder.O in
  let* unit_names = Action_builder.of_memo (run_codept ~sctx ~dir ~sandbox ~ml_kind m) in
  let* libs =
    Action_builder.of_memo
      (Resolve.Memo.peek requires_compile
       |> Memo.map ~f:(function
         | Ok libs -> libs
         | Error _ -> []))
  in
  (* Resolve each compilation unit to .cmi/.cmx paths *)
  let paths =
    List.concat_map unit_names ~f:(fun name ->
      let module_name = Module_name.of_checked_string name in
      match Modules.With_vlib.find_dep modules ~of_:m module_name with
      | Error `Parent_cycle -> []
      | Ok (_ :: _ as local_modules) ->
        (* Local module — get .cmi (and .cmx if needed) from local obj_dir *)
        List.concat_map local_modules ~f:(fun dep_module ->
          let cmi_kind = Lib_mode.Cm_kind.cmi cm_kind in
          let cmi =
            Path.build (Obj_dir.Module.cm_file_exn obj_dir dep_module ~kind:cmi_kind)
          in
          if Module.has dep_module ~ml_kind:Impl && cm_kind = Ocaml Cmx && not opaque
          then (
            let cmx =
              Path.build (Obj_dir.Module.cm_file_exn obj_dir dep_module ~kind:(Ocaml Cmx))
            in
            [ cmi; cmx ])
          else [ cmi ])
      | Ok [] ->
        (* Not local — try dependency libraries *)
        (match resolve_in_libs ~libs ~for_ module_name with
         | Some cmi -> [ cmi ]
         | None -> []))
  in
  (* Also add implicit deps (e.g. modules_before_stdlib) *)
  let implicit_paths =
    Modules.With_vlib.implicit_deps modules ~of_:m
    |> List.map ~f:(fun dep_module ->
      let cmi_kind = Lib_mode.Cm_kind.cmi cm_kind in
      Path.build (Obj_dir.Module.cm_file_exn obj_dir dep_module ~kind:cmi_kind))
  in
  Action_builder.dyn_paths_unit (Action_builder.return (paths @ implicit_paths))
;;
