open Import
open Memo.O
module Backing = Source_tree.Rules.Backing

(* The source files and directories of a recipe-built package's mount. *)
let source_inventory context candidate ~dir components =
  let name = Pkg_sources.Candidate.name candidate in
  let loc = Pkg_sources.Candidate.source_loc candidate in
  let rec descend backing = function
    | [] ->
      Backing.dir_contents backing
      >>| Result.map ~f:(Option.map ~f:(fun contents -> backing, contents))
    | component :: rest ->
      let name = Filename.of_string_exn component in
      Backing.dir_contents backing
      >>= (function
       | Error error -> Memo.return (Error error)
       | Ok (Some (_, dirs)) when Filename.Array.Set.mem dirs name ->
         descend (Backing.relative_fname backing name) rest
       | Ok _ -> Memo.return (Ok None))
  in
  Pkg_sources.mount_backing context name
  >>= function
  | None -> Memo.return None
  | Some root ->
    descend root components
    >>| (function
     | Error error ->
       User_error.raise
         ~loc
         [ Pp.textf "Unable to read %s" (Path.to_string_maybe_quoted (Backing.path root))
         ; Unix_error.Detailed.pp error
         ]
     | Ok inventory ->
       Option.map inventory ~f:(fun (backing, (files, dirs)) ->
         let files =
           Filename.Array.Set.to_list files
           |> Filename.Map.of_list_map_exn ~f:(fun file ->
             let src = Backing.relative_fname backing file |> Backing.path in
             ( file
             , Source_file_dir.copy_rule ~src ~dst:(Path.Build.relative_fname dir file) ))
         in
         files, dirs))
;;

let gen_mounted_rules context ~dir components =
  let open Build_config.Gen_rules in
  match components with
  | [] ->
    let+ candidates = Pkg_sources.candidates context in
    List.map candidates ~f:(fun candidate ->
      Pkg_sources.Candidate.name candidate
      |> Package.Name.to_string
      |> Filename.of_string_exn)
    |> Subdir_set.of_list
    |> make_empty ~dir
  | name :: rest ->
    let name = Package.Name.of_string name in
    let* candidate = Pkg_sources.find_candidate context name in
    (match candidate with
     | None -> Memo.return no_rules
     | Some candidate ->
       let+ inventory = source_inventory context candidate ~dir rest in
       let source_files, source_sub_dirs =
         match inventory with
         | None -> Path.Build.Map.empty, Path.Build.Map.empty
         | Some (files, dirs) ->
           Path.Build.Map.singleton dir files, Path.Build.Map.singleton dir dirs
       in
       (match rest, inventory with
        | [], _ ->
          let paths = Pkg_rules.candidate_paths candidate in
          let rules =
            Dune_engine.Rules.collect_unit (fun () ->
              let* () =
                Dune_engine.Rules.Produce.Alias.add_deps
                  (Alias.make Alias0.all ~dir)
                  (Action_builder.path (Path.build paths.target_dir))
              in
              let dependencies = Package_layout.materialize_dependencies context name in
              Pkg_rules.gen_mounted_rule context candidate ~dependencies)
          in
          Rules
            (Rules.create
               ~directory_targets:(Path.Build.Map.singleton paths.target_dir Loc.none)
               ~source_sub_dirs
               ~source_files
               rules)
        | _ :: _, None -> no_rules
        | _ :: _, Some _ ->
          Rules
            (Rules.create
               ~source_sub_dirs
               ~source_files
               (Memo.return Dune_engine.Rules.empty))))
;;
