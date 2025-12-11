open Import

(* Parse fine-deps file content to extract imported modules with their interface digests.
   Format v2: csexp ((intf ((mod1 crc1 file_digest1) ...)) (impl ...))
   Also supports v1 format: ((intf ((mod1 crc1) ...)) (impl ...)) for backwards compat *)
let parse_fine_deps_content content =
  match Csexp.parse_string content with
  | Error _ -> None
  | Ok sexp ->
    (match (sexp : Sexp.t) with
     | List [ List [ Atom "intf"; List intf_list ]; List [ Atom "impl"; List impl_list ] ]
       ->
       let parse_imports imports =
         List.filter_map imports ~f:(function
           (* v2 format: (mod_name crc file_digest) *)
           | Sexp.List [ Atom mod_name; Atom crc; Atom file_digest ] ->
             Some (Module_name.Unique.of_string mod_name, crc, Some file_digest)
           (* v1 format: (mod_name crc) - backwards compat, no file digest *)
           | Sexp.List [ Atom mod_name; Atom crc ] ->
             Some (Module_name.Unique.of_string mod_name, crc, None)
           | _ -> None)
       in
       Some (parse_imports intf_list, parse_imports impl_list)
     | _ -> None)
;;

(* Find .cmi file for a module by searching obj_dirs.
   Module names from ocamlobjinfo are like "Mylib__A" which becomes "mylib__A" after
   Module_name.Unique.of_string. The actual file is "mylib__A.cmi" (preserving case
   after the first char).
   Searches the primary obj_dir first, then dependency obj_dirs for cross-lib modules. *)
let find_cmi_file ~obj_dir ~dep_obj_dirs mod_name =
  let mod_str = Module_name.Unique.to_string mod_name in
  (* The unique module name is already in the right format for filenames *)
  let filename = mod_str ^ ".cmi" in
  let try_dir dir =
    let path = Path.Build.relative dir filename in
    if Sys.file_exists (Path.to_string (Path.build path)) then Some path else None
  in
  (* Search primary obj_dir first, then dependency obj_dirs *)
  match try_dir obj_dir with
  | Some _ as result -> result
  | None -> List.find_map dep_obj_dirs ~f:try_dir
;;

module Spec = struct
  type ('path, 'target) t =
    { wrapped_action : Action.t
    ; source_digest : Digest.t
    ; ocaml_digest : Digest.t
    ; flags_digest : Digest.t
    ; fine_deps_key : Digest.t
    ; targets : 'target list
    ; module_name : string
    ; cm_kind_str : string
    ; cm_file : 'target (* The .cmo/.cmx file for ocamlobjinfo *)
    ; ocamlobjinfo_path : 'path (* Path to ocamlobjinfo executable *)
    ; obj_dir : 'target (* Object directory for finding .cmi files *)
    ; dep_obj_dirs :
        'target list (* Obj dirs of dependency libraries for cross-lib .cmi lookup *)
    }

  let name = "cache-wrapper"
  let version = 1
  let is_useful_to ~memoize = memoize

  let bimap t f g =
    { t with
      targets = List.map t.targets ~f:g
    ; cm_file = g t.cm_file
    ; ocamlobjinfo_path =
        f t.ocamlobjinfo_path
        (* Note: wrapped_action path mapping would need Action.map, but since
       we're inside the same rule, paths should already be correct *)
    ; obj_dir = g t.obj_dir
    ; dep_obj_dirs = List.map t.dep_obj_dirs ~f:g
    }
  ;;

  let encode t _encode_path encode_target =
    (* Encode only serializable parts - digests determine cache key *)
    Sexp.record
      [ "source_digest", Sexp.Atom (Digest.to_string t.source_digest)
      ; "ocaml_digest", Sexp.Atom (Digest.to_string t.ocaml_digest)
      ; "flags_digest", Sexp.Atom (Digest.to_string t.flags_digest)
      ; "fine_deps_key", Sexp.Atom (Digest.to_string t.fine_deps_key)
      ; "targets", Sexp.List (List.map t.targets ~f:encode_target)
      ; "module_name", Sexp.Atom t.module_name
      ; "cm_kind", Sexp.Atom t.cm_kind_str
      ]
  ;;

  (* Verify that imported modules' .cmi files haven't changed.
     Returns true if all verifiable imports match, false if any mismatch. *)
  let verify_imports ~obj_dir ~dep_obj_dirs imports =
    let obj_dir_str = Path.Build.to_string obj_dir in
    Log.info [ Pp.textf "# fine-cache: verifying imports in %s" obj_dir_str ];
    List.for_all imports ~f:(fun (mod_name, _crc, file_digest_opt) ->
      let mod_str = Module_name.Unique.to_string mod_name in
      match file_digest_opt with
      | None ->
        Log.info [ Pp.textf "# fine-cache: %s has no file_digest (v1 format)" mod_str ];
        true
      | Some "" ->
        (* Empty file_digest means we couldn't find the .cmi during store.
           Only allow this for known stdlib/compiler modules. Project modules
           (wrapped or unwrapped) typically have underscores in their names. *)
        let has_underscore = String.exists mod_str ~f:(fun c -> Char.equal c '_') in
        let is_stdlib_module =
          (* Stdlib modules don't have underscores and start with lowercase.
             CamlinternalX modules are exception (uppercase, no underscore). *)
          (not has_underscore)
          && (String.is_prefix mod_str ~prefix:"Camlinternalformat"
              || String.is_prefix mod_str ~prefix:"Stdlib"
              || (String.length mod_str > 0
                  &&
                  let c = mod_str.[0] in
                  c >= 'a' && c <= 'z'))
        in
        if is_stdlib_module
        then (
          Log.info
            [ Pp.textf "# fine-cache: %s has empty file_digest (stdlib) - OK" mod_str ];
          true)
        else (
          Log.info
            [ Pp.textf "# fine-cache: %s has empty file_digest (cross-lib) - FAIL" mod_str
            ];
          false)
      | Some stored_digest ->
        (match find_cmi_file ~obj_dir ~dep_obj_dirs mod_name with
         | None ->
           (* Can't find .cmi file - fail verification to avoid stale cache hits. *)
           Log.info [ Pp.textf "# fine-cache: %s.cmi not found - FAIL" mod_str ];
           false
         | Some cmi_path ->
           let current_digest = Digest.file (Path.build cmi_path) |> Digest.to_string in
           if String.equal current_digest stored_digest
           then (
             Log.info [ Pp.textf "# fine-cache: %s.cmi verified (match)" mod_str ];
             true)
           else (
             Log.info
               [ Pp.textf
                   "# fine-cache: %s.cmi MISMATCH stored=%s current=%s"
                   mod_str
                   stored_digest
                   current_digest
               ];
             false)))
  ;;

  let action t ~(ectx : Action.context) ~eenv:_ =
    (* Try fine-grained cache lookup using source-based key *)
    let cache_hit =
      match Dune_cache_storage.Value.restore ~action_digest:t.fine_deps_key with
      | Dune_cache_storage.Restore_result.Restored content ->
        Log.info [ Pp.textf "# fine-cache: found deps for %s" t.module_name ];
        (match parse_fine_deps_content content with
         | Some (intf_imports, _impl_imports) ->
           (* Verify stored file digests match current .cmi files *)
           if
             not
               (verify_imports
                  ~obj_dir:t.obj_dir
                  ~dep_obj_dirs:t.dep_obj_dirs
                  intf_imports)
           then (
             Log.info [ Pp.textf "# fine-cache: dependency changed for %s" t.module_name ];
             false)
           else (
             let imported_digests =
               List.fold_left
                 intf_imports
                 ~init:Module_name.Unique.Map.empty
                 ~f:(fun acc (mod_name, crc, _file_digest) ->
                   Module_name.Unique.Map.set acc mod_name (Digest.string crc))
             in
             let fine_key =
               Fine_grained_cache.compute_fine_key
                 ~source_digest:t.source_digest
                 ~ocaml_digest:t.ocaml_digest
                 ~flags_digest:t.flags_digest
                 ~imported_cmi_digests:imported_digests
                 ~cm_kind:t.cm_kind_str
             in
             Log.info
               [ Pp.textf
                   "# fine-cache: lookup key %s for %s"
                   (Digest.to_string fine_key)
                   t.module_name
               ];
             let mode = Dune_cache_storage.Mode.default () in
             (* cm_file is the required target, others are optional *)
             let optional_targets =
               List.filter t.targets ~f:(fun target ->
                 not (Path.Build.equal target t.cm_file))
             in
             Fine_grained_cache.lookup_and_restore
               ~mode
               ~fine_key
               ~required_target:t.cm_file
               ~optional_targets)
         | None ->
           Log.info [ Pp.textf "# fine-cache: failed to parse deps for %s" t.module_name ];
           false)
      | Not_found_in_cache ->
        Log.info
          [ Pp.textf
              "# fine-cache: no deps for %s (key=%s)"
              t.module_name
              (Digest.to_string t.fine_deps_key)
          ];
        false
      | Error _ -> false
    in
    (* Check if we should verify this cache hit for reproducibility *)
    let verify_hit =
      cache_hit
      && Fine_grained_cache.Reproducibility_check.sample
           !Fine_grained_cache.reproducibility_check
    in
    if cache_hit && not verify_hit
    then (
      Log.info
        [ Pp.textf
            "# fine-cache HIT (%s): %s - skipping compilation"
            t.cm_kind_str
            t.module_name
        ];
      Fiber.return Dune_engine.Done_or_more_deps.Done)
    else if verify_hit
    then (
      (* Cache hit but we're verifying - save cached digests, recompile, compare *)
      Log.info
        [ Pp.textf
            "# fine-cache VERIFY (%s): %s - recompiling to check"
            t.cm_kind_str
            t.module_name
        ];
      let cached_digests =
        List.filter_map t.targets ~f:(fun target ->
          let path = Path.build target in
          if Sys.file_exists (Path.to_string path)
          then Some (target, Digest.file path)
          else None)
      in
      (* Remove cached cm file so compilation can overwrite it
         (cache hardlinks may be read-only). Only remove the .cmo/.cmx,
         not .cmi files which may be needed by parallel compilations. *)
      List.iter t.targets ~f:(fun target ->
        let ext = Filename.extension (Path.Build.to_string target) in
        if String.equal ext ".cmo" || String.equal ext ".cmx" || String.equal ext ".o"
        then Path.unlink_no_err (Path.build target));
      let open Fiber.O in
      let* result = ectx.exec_action t.wrapped_action in
      (* Compare fresh output with cached *)
      let fresh_digests =
        List.filter_map t.targets ~f:(fun target ->
          let path = Path.build target in
          if Sys.file_exists (Path.to_string path)
          then Some (target, Digest.file path)
          else None)
      in
      let mismatches =
        List.filter_map cached_digests ~f:(fun (target, cached_digest) ->
          match List.find fresh_digests ~f:(fun (t, _) -> Path.Build.equal t target) with
          | None -> Some (target, cached_digest, None)
          | Some (_, fresh_digest) ->
            if Digest.equal cached_digest fresh_digest
            then None
            else Some (target, cached_digest, Some fresh_digest))
      in
      (match mismatches with
       | [] ->
         Log.info
           [ Pp.textf
               "# fine-cache VERIFIED (%s): %s - outputs match"
               t.cm_kind_str
               t.module_name
           ]
       | _ ->
         Log.info
           [ Pp.textf "# fine-cache MISMATCH (%s): %s" t.cm_kind_str t.module_name ];
         List.iter mismatches ~f:(fun (target, cached, fresh_opt) ->
           let fresh_str =
             match fresh_opt with
             | None -> "missing"
             | Some fresh -> Digest.to_string fresh
           in
           Log.info
             [ Pp.textf
                 "  %s: cached=%s fresh=%s"
                 (Path.Build.to_string target)
                 (Digest.to_string cached)
                 fresh_str
             ]));
      Fiber.return result)
    else (
      Log.info
        [ Pp.textf "# fine-cache MISS (%s): %s - compiling" t.cm_kind_str t.module_name ];
      (* Execute wrapped action *)
      let open Fiber.O in
      let* result = ectx.exec_action t.wrapped_action in
      (* After successful compilation, run ocamlobjinfo and store deps *)
      match result with
      | Dune_engine.Done_or_more_deps.Done ->
        let cm_path = Path.build t.cm_file in
        (* Run ocamlobjinfo to get interface digests and store to cache *)
        let store_deps () =
          (* Use absolute path since Process.run_capture may run in different dir *)
          let cm_path_absolute = Path.to_absolute_filename cm_path in
          let* output =
            Process.run_capture
              ~display:Dune_engine.Display.Quiet
              ~dir:(Path.build (Path.Build.parent_exn t.cm_file))
              Process.Failure_mode.Strict
              t.ocamlobjinfo_path
              [ cm_path_absolute ]
          in
          (* Parse ocamlobjinfo output *)
          let ooi_list = Ocamlobjinfo.parse_with_interface_digests output in
          let ooi =
            match ooi_list with
            | [ x ] -> x
            | _ -> { Ml_kind.Dict.intf = []; impl = [] }
          in
          Log.info
            [ Pp.textf
                "# fine-cache: ocamlobjinfo for %s found %d intf deps, %d impl deps"
                t.module_name
                (List.length ooi.intf)
                (List.length ooi.impl)
            ];
          (* Format as csexp v2 with file digests for verification *)
          let content =
            let list_to_sexp imports =
              Sexp.List
                (List.map imports ~f:(fun (mod_name, crc) ->
                   (* Find the .cmi file and compute its file digest for verification *)
                   let file_digest =
                     match
                       find_cmi_file
                         ~obj_dir:t.obj_dir
                         ~dep_obj_dirs:t.dep_obj_dirs
                         mod_name
                     with
                     | Some cmi_path ->
                       Digest.file (Path.build cmi_path) |> Digest.to_string
                     | None -> ""
                   in
                   Sexp.List
                     [ Atom (Module_name.Unique.to_string mod_name)
                     ; Atom crc
                     ; Atom file_digest
                     ]))
            in
            let sexp =
              Sexp.List
                [ List [ Atom "intf"; list_to_sexp ooi.intf ]
                ; List [ Atom "impl"; list_to_sexp ooi.impl ]
                ]
            in
            Csexp.to_string sexp
          in
          (* Store fine-deps using source-based key *)
          let mode = Dune_cache_storage.Mode.default () in
          ignore
            (Dune_cache_storage.Value.store ~mode ~action_digest:t.fine_deps_key content
             : Dune_cache_storage.Store_result.t);
          (* Compute and store artifacts with fine key *)
          let imported_digests =
            List.fold_left
              ooi.intf
              ~init:Module_name.Unique.Map.empty
              ~f:(fun acc (mod_name, digest) ->
                Module_name.Unique.Map.set acc mod_name (Digest.string digest))
          in
          let fine_key =
            Fine_grained_cache.compute_fine_key
              ~source_digest:t.source_digest
              ~ocaml_digest:t.ocaml_digest
              ~flags_digest:t.flags_digest
              ~imported_cmi_digests:imported_digests
              ~cm_kind:t.cm_kind_str
          in
          Fine_grained_cache.store ~mode ~fine_key ~targets:t.targets;
          Log.info
            [ Pp.textf "# fine-cache: stored deps and artifacts for %s" t.module_name ];
          Fiber.return ()
        in
        (* Try to store deps, but don't fail the build if it doesn't work *)
        let* _store_result = Fiber.collect_errors store_deps in
        (match _store_result with
         | Ok () -> ()
         | Error exns ->
           let msgs =
             List.map exns ~f:(fun exn -> Exn_with_backtrace.to_dyn exn |> Dyn.to_string)
           in
           Log.info
             [ Pp.textf
                 "# fine-cache: failed to store deps for %s: %s"
                 t.module_name
                 (String.concat ~sep:"; " msgs)
             ]);
        Fiber.return result
      | Need_more_deps _ -> Fiber.return result)
  ;;
end

module A = Action_ext.Make_full (Spec)

let wrap
      ~wrapped_action
      ~source_digest
      ~ocaml_digest
      ~flags_digest
      ~fine_deps_key
      ~targets
      ~module_name
      ~cm_kind_str
      ~cm_file
      ~ocamlobjinfo_path
      ~obj_dir
      ~dep_obj_dirs
  =
  A.action
    { Spec.wrapped_action
    ; source_digest
    ; ocaml_digest
    ; flags_digest
    ; fine_deps_key
    ; targets
    ; module_name
    ; cm_kind_str
    ; cm_file
    ; ocamlobjinfo_path
    ; obj_dir
    ; dep_obj_dirs
    }
;;
