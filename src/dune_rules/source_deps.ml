open Import
open Memo.O

module Map_reduce =
  Source_tree.Dir.Make_map_reduce
    (Memo)
    (Monoid.Product (Monoid.Union (Path.Set)) (Monoid.Union (Path.Set)))

let files_with_filter dir ~filter =
  let* () = Memo.return () in
  let prefix_with, context_name, dir =
    match (dir : Path.t) with
    | In_source_tree dir -> Path.root, None, dir
    | otherwise ->
      let prefix_with, dir = Path.extract_build_context_dir_exn otherwise in
      let ctx_name =
        match
          Path.Build.extract_build_context_exn (Path.as_in_build_dir_exn prefix_with)
        with
        | ctx, _ -> Some (Context_name.of_string (Filename.to_string ctx))
      in
      prefix_with, ctx_name, dir
  in
  let* source_tree =
    match context_name with
    | Some name -> Source_tree.for_context name
    | None -> Memo.return Source_tree.default
  in
  Source_tree.find_dir source_tree dir
  >>= function
  | None -> Memo.return (Dep.Set.empty, Path.Set.empty)
  | Some dir ->
    let+ files, empty_directories =
      Map_reduce.map_reduce
        dir
        ~traverse:Source_dir_status.Set.all
        ~trace_event_name:"Source deps"
        ~f:(fun dir ->
          let path = Path.append_source prefix_with @@ Source_tree.Dir.path dir in
          let files =
            Source_tree.Dir.filenames dir
            |> Filename.Array.Set.to_list
            |> Path.Set.of_list_map ~f:(fun fn -> Path.relative_fname path fn)
            |> Path.Set.filter ~f:filter
          in
          let empty_directories =
            if Path.Set.is_empty files then Path.Set.singleton path else Path.Set.empty
          in
          Memo.return (files, empty_directories))
    in
    Dep.Set.of_source_files ~files ~empty_directories, files
;;

let files = files_with_filter ~filter:(Fun.const true)
