open Import
open Memo.O
module Backing = Source_tree_file.Backing

(* The source files and directories of a recipe-built package's mount. *)
let source_inventory context candidate ~dir components =
  let name = Pkg_sources.Candidate.name candidate in
  let loc = Pkg_sources.Candidate.source_loc candidate in
  Pkg_sources.mount_backing context name
  >>= function
  | None -> Memo.return None
  | Some root ->
    let components = List.map components ~f:Filename.of_string_exn in
    Backing.find_dir root components
    >>| (function
     | Error error -> Backing.unreadable ~loc root error
     | Ok inventory ->
       Option.map inventory ~f:(fun (files, dirs) ->
         let backing = List.fold_left components ~init:root ~f:Backing.relative_fname in
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
          let target_dir =
            Pkg_rules.candidate_paths candidate |> Pkg_rules.Paths.target_dir
          in
          let rules =
            Dune_engine.Rules.collect_unit (fun () ->
              let* () =
                Dune_engine.Rules.Produce.Alias.add_deps
                  (Alias.make Alias0.all ~dir)
                  (Action_builder.path (Path.build target_dir))
              in
              let dependencies = Package_layout.materialize_dependencies context name in
              Pkg_rules.gen_mounted_rule context candidate ~dependencies)
          in
          Rules
            (Rules.create
               ~directory_targets:(Path.Build.Map.singleton target_dir Loc.none)
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
