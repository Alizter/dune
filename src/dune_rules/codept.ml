open Import
open Memo.O

(* For each dependency library, get its modules (resolving Local libs via
   Dir_contents). Returns a list of (modules, obj_dir) pairs. *)
let resolve_lib_modules ~sctx ~libs ~for_ =
  Memo.List.filter_map libs ~f:(fun lib ->
    let info = Lib.info lib in
    let obj_dir = Lib_info.obj_dir info in
    match Lib_info.modules info ~for_ with
    | External (Some modules) -> Memo.return (Some (modules, obj_dir))
    | External None -> Memo.return None
    | Local ->
      let+ modules_opt = Dir_contents.modules_of_lib sctx lib ~for_ in
      Option.map modules_opt ~f:(fun modules -> modules, obj_dir))
;;

let resolve_in_lib_modules ~lib_modules name =
  List.find_map lib_modules ~f:(fun (modules, obj_dir) ->
    match Modules.With_vlib.find modules name with
    | Some module_ -> Obj_dir.Module.cm_file obj_dir module_ ~kind:(Ocaml Cmi)
    | None -> None)
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
  let local_obj_map = Modules.With_vlib.obj_map modules in
  let cm_files_of dep_module =
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
    else [ cmi ]
  in
  Command.Args.Dyn
    (let open Action_builder.O in
     let* unit_names =
       Action_builder.of_memo (run_codept ~sctx ~dir ~sandbox ~ml_kind m)
     in
     let* libs, lib_modules =
       Action_builder.of_memo
         (let open Memo.O in
          let* libs =
            Resolve.Memo.peek requires_compile
            |> Memo.map ~f:(function
              | Ok libs -> libs
              | Error _ -> [])
          in
          let+ lib_modules = resolve_lib_modules ~sctx ~libs ~for_ in
          libs, lib_modules)
     in
     let paths =
       List.concat_map unit_names ~f:(fun name ->
         let module_name = Module_name.of_checked_string name in
         match Modules.With_vlib.find_dep modules ~of_:m module_name with
         | Error `Parent_cycle -> []
         | Ok (_ :: _ as local_modules) -> List.concat_map local_modules ~f:cm_files_of
         | Ok [] ->
           let obj_name = Module_name.Unique.of_string name in
           (match Module_name.Unique.Map.find local_obj_map obj_name with
            | Some sourced -> cm_files_of (Modules.Sourced_module.to_module sourced)
            | None ->
              (match resolve_in_lib_modules ~lib_modules module_name with
               | Some cmi -> [ cmi ]
               | None -> [])))
     in
     let alias_paths =
       Modules.With_vlib.alias_for modules m |> List.concat_map ~f:cm_files_of
     in
     let implicit_paths =
       Modules.With_vlib.implicit_deps modules ~of_:m
       |> List.map ~f:(fun dep_module ->
         let cmi_kind = Lib_mode.Cm_kind.cmi cm_kind in
         Path.build (Obj_dir.Module.cm_file_exn obj_dir dep_module ~kind:cmi_kind))
     in
     let all_paths = paths @ alias_paths @ implicit_paths in
     (* -I flags: include dirs of resolved deps + all library obj_dirs *)
     let lib_dirs =
       List.concat_map libs ~f:(fun lib ->
         let obj_dir = Lib_info.obj_dir (Lib.info lib) in
         let cmi_dir =
           match cm_kind with
           | Lib_mode.Cm_kind.Melange _ -> Obj_dir.public_cmi_melange_dir obj_dir
           | Ocaml _ -> Obj_dir.public_cmi_ocaml_dir obj_dir
         in
         [ cmi_dir ])
     in
     let dirs =
       List.map all_paths ~f:Path.parent_exn
       |> List.rev_append lib_dirs
       |> Path.Set.of_list
       |> Path.Set.to_list
     in
     let iflags =
       List.concat_map dirs ~f:(fun d -> [ Command.Args.A "-I"; Path d ])
     in
     let+ () = Action_builder.dyn_paths_unit (Action_builder.return all_paths) in
     Command.Args.S (iflags @ [ Hidden_deps (Dep.Set.of_files all_paths) ]))
;;
