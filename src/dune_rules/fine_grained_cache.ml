open Import

module Reproducibility_check = struct
  type t =
    | Skip
    | Check_with_probability of float
    | Check

  let sample = function
    | Skip -> false
    | Check_with_probability p -> Random.float 1. < p
    | Check -> true
  ;;
end

let reproducibility_check =
  match Sys.getenv_opt "DUNE_FINE_CACHE_CHECK" with
  | Some "1" | Some "true" -> ref Reproducibility_check.Check
  | Some p ->
    (try
       let prob = Stdlib.float_of_string p in
       ref (Reproducibility_check.Check_with_probability prob)
     with
     | _ -> ref Reproducibility_check.Skip)
  | None -> ref Reproducibility_check.Skip
;;

let compute_fine_key
      ~source_digest
      ~ocaml_digest
      ~flags_digest
      ~imported_cmi_digests
      ~cm_kind
  =
  (* Sort the imported modules for deterministic hashing *)
  let sorted_deps =
    Module_name.Unique.Map.to_list imported_cmi_digests
    |> List.sort ~compare:(fun (m1, _) (m2, _) -> Module_name.Unique.compare m1 m2)
    |> List.map ~f:(fun (m, d) -> Module_name.Unique.to_string m, d)
  in
  (* Use a version prefix to allow future changes to the key format.
     Include cm_kind so cmo and cmx have different cache keys. *)
  Digest.generic
    ("fine-cache-v2", source_digest, ocaml_digest, flags_digest, sorted_deps, cm_kind)
;;

let lookup_and_restore ~mode ~fine_key ~required_target ~optional_targets =
  let module Layout = Dune_cache_storage.Layout in
  let file_path ~file_digest = Lazy.force (Layout.file_path ~file_digest) in
  (* Look up metadata for the fine key *)
  match Dune_cache_storage.Artifacts.list ~rule_digest:fine_key with
  | Dune_cache_storage.Restore_result.Restored entries ->
    (* Check if required target is present and restorable *)
    let required_basename = Path.Build.basename required_target in
    let required_entry =
      List.find
        entries
        ~f:(fun { Dune_cache_storage.Artifacts.Metadata_entry.path; digest } ->
          String.equal (Filename.basename path) required_basename
          &&
          match digest with
          | None -> false
          | Some file_digest ->
            let src = file_path ~file_digest in
            Sys.file_exists (Path.to_string src))
    in
    (match required_entry with
     | None ->
       Log.info
         [ Pp.textf
             "# fine-grained cache: required target %s not found in entries"
             (Path.Build.to_string required_target)
         ];
       false
     | Some { digest = None; _ } -> false
     | Some { digest = Some file_digest; _ } ->
       (* Restore the required target first *)
       let src = file_path ~file_digest in
       let dst_path = Path.build required_target in
       let required_restored =
         try
           Path.mkdir_p (Path.build (Path.Build.parent_exn required_target));
           Path.unlink_no_err dst_path;
           (match (mode : Dune_cache_storage.Mode.t) with
            | Hardlink -> Path.link src dst_path
            | Copy -> Io.copy_file ~src ~dst:dst_path ());
           if Sys.file_exists (Path.to_string dst_path)
           then (
             Log.info
               [ Pp.textf
                   "# fine-grained cache: restored %s"
                   (Path.Build.to_string required_target)
               ];
             true)
           else false
         with
         | _ -> false
       in
       if not required_restored
       then false
       else (
         (* Try to restore optional targets - don't fail if they're missing *)
         List.iter optional_targets ~f:(fun target ->
           let basename = Path.Build.basename target in
           let entry =
             List.find
               entries
               ~f:(fun { Dune_cache_storage.Artifacts.Metadata_entry.path; _ } ->
                 String.equal (Filename.basename path) basename)
           in
           match entry with
           | None ->
             Log.info
               [ Pp.textf
                   "# fine-grained cache: optional target %s not in cache (OK)"
                   (Path.Build.to_string target)
               ]
           | Some { digest = None; _ } -> ()
           | Some { digest = Some file_digest; _ } ->
             let src = file_path ~file_digest in
             let dst_path = Path.build target in
             (try
                Path.mkdir_p (Path.build (Path.Build.parent_exn target));
                Path.unlink_no_err dst_path;
                (match (mode : Dune_cache_storage.Mode.t) with
                 | Hardlink -> Path.link src dst_path
                 | Copy -> Io.copy_file ~src ~dst:dst_path ());
                if Sys.file_exists (Path.to_string dst_path)
                then
                  Log.info
                    [ Pp.textf
                        "# fine-grained cache: restored %s"
                        (Path.Build.to_string target)
                    ]
              with
              | _ -> ()));
         true))
  | Not_found_in_cache -> false
  | Error _ -> false
;;

let store ~mode ~fine_key ~targets =
  let module Layout = Dune_cache_storage.Layout in
  (* Store each target file to the cache and create metadata entry *)
  let entries =
    List.filter_map targets ~f:(fun target ->
      let path = Path.build target in
      let path_str = Path.to_string path in
      if Sys.file_exists path_str
      then (
        let file_digest = Digest.file path in
        (* Store the file content to the cache location *)
        let path_in_cache = Lazy.force (Layout.file_path ~file_digest) in
        (try
           Path.mkdir_p (Path.parent_exn path_in_cache);
           match (mode : Dune_cache_storage.Mode.t) with
           | Hardlink ->
             (* Try to hardlink, fall back to copy if it fails *)
             (try Path.link path path_in_cache with
              | Unix.Unix_error (Unix.EEXIST, _, _) -> ()
              | Unix.Unix_error _ -> Io.copy_file ~src:path ~dst:path_in_cache ())
           | Copy -> Io.copy_file ~src:path ~dst:path_in_cache ()
         with
         | _ -> ());
        Some
          { Dune_cache_storage.Artifacts.Metadata_entry.path = Path.Build.basename target
          ; digest = Some file_digest
          })
      else None)
  in
  if not (List.is_empty entries)
  then
    ignore
      (Dune_cache_storage.Artifacts.Metadata_file.store
         ~mode:Dune_cache_storage.Mode.Copy
         ~rule_digest:fine_key
         { metadata = []; entries }
       : Dune_cache_storage.Store_result.t)
;;
