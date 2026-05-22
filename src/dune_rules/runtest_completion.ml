open Import
open Memo.O

let split_token ~cwd token =
  match String.rindex_opt token '/' with
  | None -> cwd, "", token
  | Some i ->
    let parent_string = String.sub token ~pos:0 ~len:i in
    let prefix = String.sub token ~pos:(i + 1) ~len:(String.length token - i - 1) in
    let parent =
      if String.is_empty parent_string
      then cwd
      else Path.Source.relative cwd parent_string
    in
    parent, parent_string, prefix
;;

let super_context { Main.scontexts; _ } =
  match Context_name.Map.find scontexts Context_name.default with
  | Some sctx -> Some sctx
  | None ->
    (match Context_name.Map.to_list scontexts with
     | [ (_, sctx) ] -> Some sctx
     | [] | _ :: _ :: _ -> None)
;;

let candidates ~cwd ~token =
  let parent_dir, parent_string, prefix = split_token ~cwd token in
  let with_parent basename =
    if String.is_empty parent_string then basename else parent_string ^ "/" ^ basename
  in
  let prefix_matches basename = String.starts_with basename ~prefix in
  let* setup = Main.get () in
  match super_context setup with
  | None -> Memo.return []
  | Some sctx ->
    Source_tree.find_dir parent_dir
    >>= (function
     | None -> Memo.return []
     | Some source_dir ->
       let+ cram_candidates =
         Cram_rules.cram_tests source_dir
         >>| List.filter_map ~f:(fun result ->
           Result.to_option result
           |> Option.bind ~f:(fun test ->
             let basename =
               Cram_test.path test |> Path.Source.basename |> Filename.to_string
             in
             Option.some_if (prefix_matches basename) (with_parent basename)))
       and+ ml_candidates =
         let build_dir =
           Path.Build.append_source
             (Context.build_dir (Super_context.context sctx))
             parent_dir
         in
         let* dir_contents = Dir_contents.get sctx ~dir:build_dir in
         let+ ml_sources = Dir_contents.ml dir_contents ~for_:Ocaml in
         let source_files = Source_tree.Dir.filenames source_dir in
         Ml_sources.runtest_files ml_sources ~dir:parent_dir
         |> Filename.Set.to_list
         |> List.filter_map ~f:(fun filename ->
           let basename = Filename.to_string filename in
           Option.some_if
             (Filename.Array.Set.mem source_files filename && prefix_matches basename)
             (with_parent basename))
       and+ dir_candidates =
         Memo.return
           (Source_tree.Dir.sub_dirs source_dir
            |> Filename.Array.Map.to_list
            |> List.filter_map ~f:(fun (dirname, _) ->
              let basename = Filename.to_string dirname in
              Option.some_if
                ((not (Cram_test.is_cram_suffix dirname)) && prefix_matches basename)
                (with_parent basename ^ "/")))
       in
       List.concat [ cram_candidates; ml_candidates; dir_candidates ]
       |> String.Set.of_list
       |> String.Set.to_list)
;;
