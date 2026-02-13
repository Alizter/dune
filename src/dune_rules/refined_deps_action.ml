open Import
open Fiber.O
open Dune_engine.Action.Ext

module T = struct
  type ('path, 'target) t =
    { ocamlobjinfo : 'path
    ; input : 'path
    ; output : 'target
    ; mapping : (Module_name.Unique.t * 'path) list
    }

  let name = "refined-deps"
  let version = 1
  let is_useful_to ~memoize:_ = false

  let encode { ocamlobjinfo; input; output; mapping } path_to_sexp target_to_sexp =
    let open Sexp in
    List
      [ path_to_sexp ocamlobjinfo
      ; path_to_sexp input
      ; target_to_sexp output
      ; List
          (List.map mapping ~f:(fun (name, path) ->
             List [ Atom (Module_name.Unique.to_string name); path_to_sexp path ]))
      ]
  ;;

  let bimap { ocamlobjinfo; input; output; mapping } f g =
    { ocamlobjinfo = f ocamlobjinfo
    ; input = f input
    ; output = g output
    ; mapping = List.map mapping ~f:(fun (name, path) -> name, f path)
    }
  ;;

  let action
        { ocamlobjinfo; input; output; mapping }
        ~(ectx : Exec.context)
        ~(eenv : Exec.env)
    =
    let mapping_table = Module_name.Unique.Map.of_list_exn mapping in
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
    (* Parse ocamlobjinfo output to get imported interfaces *)
    let parsed = Ocamlobjinfo.parse stdout in
    let imported_intfs =
      List.concat_map parsed ~f:(fun t -> Module_name.Unique.Set.to_list t.intf)
    in
    (* Look up each imported interface in the mapping *)
    let refined_paths =
      List.filter_map imported_intfs ~f:(fun name ->
        Module_name.Unique.Map.find mapping_table name)
    in
    (* Write paths to output file, one per line *)
    let content = String.concat ~sep:"\n" (List.map refined_paths ~f:Path.to_string) in
    Io.write_file (Path.build output) content;
    Fiber.return ()
  ;;
end

module M = Action_ext.Make (T)

let action ~ocamlobjinfo ~input ~output ~mapping =
  M.action { T.ocamlobjinfo; input; output; mapping }
;;
