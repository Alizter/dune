open Import
open Fiber.O
open Dune_engine.Action.Ext

module T = struct
  type ('path, 'target) t =
    { ocamlobjinfo : 'path
    ; input : 'path
    ; source : 'path
    ; output : 'target
    ; mapping : (Module_name.Unique.t * 'path) list
    }

  let name = "refined-deps"
  let version = 2
  let is_useful_to ~memoize:_ = false

  let encode { ocamlobjinfo; input; source; output; mapping } path_to_sexp target_to_sexp =
    let open Sexp in
    List
      [ path_to_sexp ocamlobjinfo
      ; path_to_sexp input
      ; path_to_sexp source
      ; target_to_sexp output
      ; List
          (List.map mapping ~f:(fun (name, path) ->
             List [ Atom (Module_name.Unique.to_string name); path_to_sexp path ]))
      ]
  ;;

  let bimap { ocamlobjinfo; input; source; output; mapping } f g =
    { ocamlobjinfo = f ocamlobjinfo
    ; input = f input
    ; source = f source
    ; output = g output
    ; mapping = List.map mapping ~f:(fun (name, path) -> name, f path)
    }
  ;;

  let action
        { ocamlobjinfo; input; source; output; mapping }
        ~(ectx : Exec.context)
        ~(eenv : Exec.env)
    =
    let mapping_table = Module_name.Unique.Map.of_list_exn mapping in
    (* Build inverse mapping to find module name for input path (to exclude self-references) *)
    let input_module_name =
      List.find_map mapping ~f:(fun (name, path) ->
        if Path.equal path input then Some name else None)
    in
    (* Run ocamlobjinfo and capture stdout *)
    let* stdout =
      Process.run_capture
        Process.Failure_mode.Strict
        ocamlobjinfo
        [ Path.to_string input ]
        ~display:Quiet
        ~dir:eenv.working_dir
        ~env:eenv.env
        ~metadata:ectx.metadata
        ~stderr_to:eenv.stderr_to
        ~stdin_from:eenv.stdin_from
    in
    (* Parse ocamlobjinfo output to get imported interfaces, excluding self *)
    let parsed = Ocamlobjinfo.parse stdout in
    let imported_intfs =
      let all =
        List.concat_map parsed ~f:(fun t -> Module_name.Unique.Set.to_list t.intf)
      in
      match input_module_name with
      | None -> all
      | Some self ->
        List.filter all ~f:(fun name -> not (Module_name.Unique.equal name self))
    in
    (* Look up each imported interface in the mapping *)
    let refined_paths =
      List.filter_map imported_intfs ~f:(fun name ->
        Module_name.Unique.Map.find mapping_table name)
    in
    (* Write paths to output file: source file first, then .cmi deps *)
    let all_paths = source :: refined_paths in
    let content = String.concat ~sep:"\n" (List.map all_paths ~f:Path.to_string) in
    Io.write_file (Path.build output) content;
    Fiber.return ()
  ;;
end

module M = Action_ext.Make (T)

let action ~ocamlobjinfo ~input ~source ~output ~mapping =
  M.action { T.ocamlobjinfo; input; source; output; mapping }
;;
