open Import
open Action_builder.O

type dependency =
  { loc : Loc.t
  ; name : Package.Name.t
  }

let rec dir_contents ~loc dir =
  let open Memo.O in
  Fs_memo.dir_contents dir
  >>= function
  | Error e -> Unix_error.Detailed.raise e
  | Ok contents ->
    Fs_memo.Dir_contents.to_list contents
    |> Memo.parallel_map ~f:(fun (entry, kind) ->
      let path = Path.Outside_build_dir.relative_fname dir entry in
      match kind with
      | Unix.S_REG -> Memo.return [ path ]
      | S_DIR -> dir_contents ~loc path
      | _ ->
        User_error.raise
          ~loc
          [ Pp.text "Encountered a special file while expanding dependency." ])
    >>| List.concat
;;

let depend_on_found { loc; name } ~dune_version = function
  | Some (Package_db.Build build) | Some (Opam build) -> build
  | Some (Local _) -> Action_builder.return ()
  | Some (Installed package) ->
    if dune_version < (2, 9)
    then
      Action_builder.fail
        { fail =
            (fun () ->
              User_error.raise
                ~loc
                [ Pp.textf
                    "Dependency on an installed package requires at least (lang dune 2.9)"
                ])
        }
    else
      (let open Memo.O in
       Memo.parallel_map package.files ~f:(fun (section, entries) ->
         let dir = Section.Map.find_exn package.sections section in
         Memo.parallel_map entries ~f:(fun { kind; dst } ->
           let path = Path.append_local dir (Install.Entry.Dst.local dst) in
           match kind with
           | File -> Memo.return [ path ]
           | Directory ->
             Path.as_outside_build_dir_exn path
             |> dir_contents ~loc
             >>| List.rev_map ~f:Path.outside_build_dir)
         >>| List.concat)
       >>| List.concat)
      |> Action_builder.of_memo
      >>= Action_builder.paths
  | None ->
    Action_builder.fail
      { fail =
          (fun () ->
            User_error.raise
              ~loc
              [ Pp.textf "Package %s does not exist" (Package.Name.to_string name) ])
      }
;;

let depend context ~dune_version dependency =
  let* package_db = Action_builder.of_memo (Package_db.create context) in
  let* found =
    Action_builder.of_memo (Package_db.find_package package_db dependency.name)
  in
  depend_on_found dependency ~dune_version found
;;

let materialize context ~dune_version dependencies =
  (* Evaluate the complete package set against one layout so root-section
     collisions are detected across the set. *)
  let* package_db = Action_builder.of_memo (Package_db.create context) in
  let* classified =
    Action_builder.List.map dependencies ~f:(fun dependency ->
      let+ found =
        Action_builder.of_memo (Package_db.find_package package_db dependency.name)
      in
      dependency, found)
  in
  let local_package_names =
    List.filter_map classified ~f:(fun (_, found) ->
      match found with
      | Some (Package_db.Local package) -> Some (Package.name package)
      | _ -> None)
    |> Package.Name.Set.of_list
  in
  let* env =
    if Package.Name.Set.is_empty local_package_names
    then Action_builder.return Env.empty
    else Install_layout.env context local_package_names
  in
  let* binaries =
    if Package.Name.Set.is_empty local_package_names
    then Action_builder.return Filename.Map.empty
    else Action_builder.of_memo (Install_layout.binaries context local_package_names)
  in
  let packages =
    let install_root = Install_layout.root context local_package_names |> Path.build in
    List.fold_left classified ~init:Package.Name.Map.empty ~f:(fun packages (_, found) ->
      match found with
      | Some (Package_db.Local package) ->
        Package.Name.Map.set
          packages
          (Package.name package)
          ( Package_deps.variables package
          , Package_deps.Paths.of_local_package package ~install_root )
      | _ -> packages)
  in
  let+ () =
    Action_builder.List.iter classified ~f:(fun (dependency, found) ->
      depend_on_found dependency ~dune_version found)
  in
  { Package_deps.env; binaries; packages }
;;
