open Import
open Memo.O

let super_context { Main.scontexts; _ } =
  match Context_name.Map.find scontexts Context_name.default with
  | Some sctx -> Some sctx
  | None ->
    (match Context_name.Map.to_list scontexts with
     | [ (_, sctx) ] -> Some sctx
     | [] | _ :: _ :: _ -> None)
;;

let rec completion_trie sctx source_dir =
  let dir = Source_tree.Dir.path source_dir in
  let+ cram_tests =
    Cram_rules.cram_tests source_dir
    >>| List.filter_map ~f:(fun result ->
      Result.to_option result
      |> Option.map ~f:(fun test ->
        Cram_test.path test |> Path.Source.basename |> Filename.to_string))
  and+ ml_tests =
    let build_dir =
      Path.Build.append_source (Context.build_dir (Super_context.context sctx)) dir
    in
    let* dir_contents = Dir_contents.get sctx ~dir:build_dir in
    let+ ml_sources = Dir_contents.ml dir_contents ~for_:Ocaml in
    let source_files = Source_tree.Dir.filenames source_dir in
    Ml_sources.runtest_files ml_sources ~dir
    |> Filename.Set.to_list
    |> List.filter_map ~f:(fun filename ->
      Option.some_if
        (Filename.Array.Set.mem source_files filename)
        (Filename.to_string filename))
  in
  let directories =
    Source_tree.Dir.sub_dirs source_dir
    |> Filename.Array.Map.to_list
    |> List.filter_map ~f:(fun (name, sub_dir) ->
      if Cram_test.is_cram_suffix name
      then None
      else (
        let child =
          Memo.lazy_ ~name:"runtest-completion-directory" (fun () ->
            let* sub_dir = Source_tree.Dir.sub_dir_as_t sub_dir in
            completion_trie sctx sub_dir)
        in
        Some (Filename.to_string name, Path_completion.expandable child)))
  in
  Path_completion.create ~values:(cram_tests @ ml_tests) ~directories
;;

let candidates ~cwd ~token =
  let* setup = Main.get () in
  match super_context setup with
  | None -> Memo.return []
  | Some sctx ->
    let* root = Source_tree.root () in
    let* trie = completion_trie sctx root in
    Path_completion.candidates trie ~cwd ~token
;;
