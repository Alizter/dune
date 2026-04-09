open Import
module F = Dune_index_format

let dune_index_dump sctx ~dir =
  Super_context.resolve_program
    sctx
    ~dir
    "dune-index-dump"
    ~loc:None
    ~hint:"opam install dune-index-dump"
;;

(** Collect all impl file sets for a given (comp_unit, id) across all extractions *)
let build_impl_file_index (extractions : F.uid_entry list list) =
  let tbl = ref String.Map.empty in
  List.iter extractions ~f:(fun entries ->
    List.iter entries ~f:(fun (e : F.uid_entry) ->
      if String.equal e.kind "impl"
      then (
        let files =
          List.map e.locs ~f:(fun (l : F.lid) -> (Loc.start l.loc).pos_fname)
          |> String.Set.of_list
        in
        let key = e.comp_unit ^ ":" ^ string_of_int e.id in
        tbl
        := String.Map.update !tbl key ~f:(function
             | None -> Some files
             | Some existing -> Some (String.Set.union existing files)))));
  !tbl
;;

(* A related_uids group of 2 is normal: [intf] + impl UID. >2 means
   additional UIDs linked via include or module alias re-exports, so
   the export is re-exported through the wrapper — skip it. *)
let is_reexport (e : F.uid_entry) = e.related_group_size > 2

let is_entry_module comp_unit modules =
  let comp_unit = String.lowercase comp_unit in
  let entry_modules = Modules.entry_modules modules in
  List.exists entry_modules ~f:(fun m ->
    let obj = Module.obj_name m |> Module_name.Unique.to_string in
    String.equal (String.lowercase obj) comp_unit)
;;

let find_module_by_comp_unit comp_unit modules =
  let comp_unit = String.lowercase comp_unit in
  Modules.fold_user_written modules ~init:None ~f:(fun m acc ->
    match acc with
    | Some _ -> acc
    | None ->
      let obj = Module.obj_name m |> Module_name.Unique.to_string in
      if String.equal (String.lowercase obj) comp_unit then Some m else None)
;;

let is_own_module comp_unit modules =
  Option.is_some (find_module_by_comp_unit comp_unit modules)
;;

(** Find the defining interface location for the export. Uses the module
    abstraction to identify the interface file (handles all dialects),
    then finds the matching loc from the UID's locs list. *)
let defining_loc (e : F.uid_entry) ~modules =
  let open Option.O in
  let* m = find_module_by_comp_unit e.comp_unit modules in
  let* intf_path = Module.source_without_pp m ~ml_kind:Intf in
  let intf_file = Path.drop_optional_build_context intf_path |> Path.to_string in
  List.find e.locs ~f:(fun (l : F.lid) ->
    String.equal (Loc.start l.loc).Lexing.pos_fname intf_file)
;;

(** Run dune-index-dump on an index file and return parsed entries. *)
let run_dump prog ~context_dir ~index_path ~loc =
  let open Action_builder.O in
  let+ output =
    let action =
      let+ action =
        Command.run' ~dir:(Path.build context_dir) prog [ Dep (Path.build index_path) ]
      in
      { Rule.Anonymous_action.action; loc; dir = context_dir; alias = Some Alias0.unused }
    in
    Dune_engine.Build_system.execute_action_stdout action |> Action_builder.of_memo
  in
  F.of_csexp_string output
;;

(** Collect index paths for dependent stanzas *)
let dependent_index_paths context_name libs =
  let open Memo.O in
  let* { Revdep_rules.Dependents.libs = dep_libs; dirs = dep_dirs } =
    Revdep_rules.Dependents.find context_name libs
  in
  let lib_paths =
    Lib.Set.to_list dep_libs
    |> List.filter_map ~f:(fun lib ->
      Lib.Local.of_lib lib
      |> Option.map ~f:(fun local ->
        Lib.Local.obj_dir local |> Ocaml_index.index_path_in_obj_dir))
  in
  let+ dir_paths =
    Path.Build.Set.to_list dep_dirs
    |> Memo.List.filter_map ~f:(fun dir ->
      Dune_load.stanzas_in_dir dir
      >>= function
      | None -> Memo.return None
      | Some dune_file ->
        Dune_file.stanzas dune_file
        >>| List.find_map ~f:(fun stanza ->
          match Stanza.repr stanza with
          | Executables.T exes | Tests.T { exes; _ } ->
            Some (Executables.obj_dir ~dir exes |> Ocaml_index.index_path_in_obj_dir)
          | _ -> None))
  in
  lib_paths @ dir_paths
;;

let gen_rules sctx cctx ~loc ~dir ~modules ~lib ~extra_index_paths =
  let obj_dir = Compilation_context.obj_dir cctx in
  let index_path = Ocaml_index.index_path_in_obj_dir obj_dir in
  let context_dir =
    Compilation_context.context cctx |> Context.name |> Context_name.build_dir
  in
  let is_unused_export ~skip_public_entry_modules impl_index (e : F.uid_entry) =
    String.equal e.kind "intf"
    && is_own_module e.comp_unit modules
    && (not (is_reexport e))
    && (match e.impl_id with
        | Some iid ->
          let key = e.comp_unit ^ ":" ^ string_of_int iid in
          let impl_files =
            String.Map.find impl_index key |> Option.value ~default:String.Set.empty
          in
          let defining_impl =
            let open Option.O in
            let* m = find_module_by_comp_unit e.comp_unit modules in
            let+ impl_path = Module.source_without_pp m ~ml_kind:Impl in
            Path.drop_optional_build_context impl_path |> Path.to_string
          in
          (match defining_impl with
           | Some ml -> String.Set.for_all impl_files ~f:(String.equal ml)
           | None -> true)
        | None -> false)
    && ((not skip_public_entry_modules)
        || not
             (match lib with
              | Some (lib : Library.t) ->
                (match lib.visibility with
                 | Public _ -> is_entry_module e.comp_unit modules
                 | Private _ -> false)
              | None -> false))
  in
  let report_unused alias_name ~skip_public_entry_modules =
    let alias = Alias.make alias_name ~dir in
    Rules.Produce.Alias.add_action
      alias
      ~loc
      (let open Action_builder.O in
       let* prog = dune_index_dump sctx ~dir in
       let* own = run_dump prog ~context_dir ~index_path ~loc in
       let* deps =
         Action_builder.List.map extra_index_paths ~f:(fun dep_index ->
           run_dump prog ~context_dir ~index_path:dep_index ~loc)
       in
       let all_extractions = own :: deps in
       let impl_index = build_impl_file_index all_extractions in
       let unused =
         List.filter own ~f:(is_unused_export ~skip_public_entry_modules impl_index)
       in
       let+ _ =
         Action_builder.List.map unused ~f:(fun (e : F.uid_entry) ->
           match defining_loc e ~modules with
           | Some (l : F.lid) ->
             Action_builder.fail
               { fail =
                   (fun () ->
                     User_error.raise ~loc:l.loc [ Pp.textf "unused export %s" l.name ])
               }
           | None -> Action_builder.return ())
       in
       Action.Full.make (Action.progn []))
  in
  let open Memo.O in
  let* () = report_unused Alias0.unused ~skip_public_entry_modules:true in
  report_unused Alias0.unused_all ~skip_public_entry_modules:false
;;

let gen_rules_for_lib sctx cctx (lib : Library.t) ~dir =
  (* :eyebrow: *)
  if Library.is_virtual lib
  then Memo.return ()
  else (
    let modules = Compilation_context.modules cctx |> Modules.With_vlib.drop_vlib in
    (* Skip only explicitly unwrapped libraries. Singleton and wrapped are analysed. *)
    if
      match lib.wrapped with
      | Lib_info.Inherited.From _ -> false
      | This w -> not (Wrapped.to_bool w)
    then Memo.return ()
    else
      let open Memo.O in
      let context_name = Compilation_context.context cctx |> Context.name in
      let* extra_index_paths =
        let scope = Compilation_context.scope cctx in
        let src_dir = dir |> Path.Build.drop_build_context_exn in
        let lib_id = Library.to_lib_id ~src_dir lib in
        Lib.DB.find_lib_id (Scope.libs scope) (Local lib_id)
        >>= function
        | None -> Memo.return []
        | Some this_lib -> dependent_index_paths context_name [ this_lib ]
      in
      gen_rules
        sctx
        cctx
        ~loc:lib.buildable.loc
        ~dir
        ~modules
        ~lib:(Some lib)
        ~extra_index_paths)
;;

let gen_rules_for_exe sctx cctx (exes : Executables.t) ~dir =
  let modules = Compilation_context.modules cctx |> Modules.With_vlib.drop_vlib in
  gen_rules
    sctx
    cctx
    ~loc:exes.buildable.loc
    ~dir
    ~modules
    ~lib:None
    ~extra_index_paths:[]
;;
