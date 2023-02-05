open Import
module Alias = Dune_engine.Alias

type t =
  { name : Alias.Name.t
  ; recursive : bool
  ; dir : Path.Source.t
  ; contexts : Dune_rules.Context.t list
  }

let pp { name; recursive; dir; contexts = _ } =
  let open Pp.O in
  let s =
    (if recursive then "@" else "@@")
    ^ Path.Source.to_string (Path.Source.relative dir (Alias.Name.to_string name))
  in
  let pp = Pp.verbatim "alias" ++ Pp.space ++ Pp.verbatim s in
  if recursive then Pp.verbatim "recursive" ++ Pp.space ++ pp else pp
;;

let in_dir ~name ~recursive ~contexts dir =
  let checked = Util.check_path contexts dir in
  match checked with
  | External _ ->
    User_error.raise
      [ Pp.textf "@@ on the command line must be followed by a relative path" ]
  | In_source_dir dir -> { dir; recursive; name; contexts }
  | In_install_dir _ ->
    User_error.raise
      [ Pp.textf
          "Invalid alias: %s."
          (Path.to_string_maybe_quoted (Path.build Dune_engine.Dpath.Build.install_dir))
      ; Pp.textf "There are no aliases in %s." (Path.to_string_maybe_quoted dir)
      ]
  | In_build_dir (ctx, dir) ->
    { dir
    ; recursive
    ; name
    ; contexts =
        [ List.find_exn contexts ~f:(fun c ->
            Context_name.equal (Context.name c) ctx.name)
        ]
    }
;;

let of_string (root : Workspace_root.t) ~recursive s ~contexts =
  let path = Path.relative Path.root (root.reach_from_root_prefix ^ s) in
  if Path.is_root path
  then
    User_error.raise
      [ Pp.textf "@ on the command line must be followed by a valid alias name" ]
  else (
    let dir = Path.parent_exn path in
    let name = Alias.Name.of_string (Path.basename path) in
    in_dir ~name ~recursive ~contexts dir)
;;

let find_dir_specified_on_command_line ~dir =
  let open Memo.O in
  Source_tree.find_dir dir
  >>| function
  | Some dir -> dir
  | None ->
    User_error.raise
      [ Pp.textf
          "Don't know about directory %s specified on the command line!"
          (Path.Source.to_string_maybe_quoted dir)
      ]
;;

let dep_on_alias_multi_contexts ~dir ~name ~contexts =
  ignore (find_dir_specified_on_command_line ~dir : _ Memo.t);
  let context_to_alias_expansion ctx =
    let ctx_dir = Context_name.build_dir ctx in
    let dir = Path.Build.(append_source ctx_dir dir) in
    Action_builder.alias (Alias.make ~dir name)
  in
  Action_builder.all_unit (List.map contexts ~f:context_to_alias_expansion)
;;

let dep_on_alias_rec_multi_contexts ~dir:src_dir ~name ~contexts =
  let open Action_builder.O in
  let* dir = Action_builder.of_memo (find_dir_specified_on_command_line ~dir:src_dir) in
  let* alias_statuses =
    Action_builder.all
      (List.map contexts ~f:(fun ctx ->
         let dir =
           Path.Build.append_source
             (Context_name.build_dir ctx)
             (Source_tree.Dir.path dir)
         in
         Dune_rules.Alias_rec.dep_on_alias_rec name dir))
  in
  let is_nonempty =
    List.exists alias_statuses ~f:(fun (x : Action_builder.Alias_status.t) ->
      match x with
      | Defined -> true
      | Not_defined -> false)
  in
  if (not is_nonempty) && not (Alias.is_standard name)
  then
    let+ load_dir =
      Action_builder.all
      @@ List.map contexts ~f:(fun ctx ->
        let dir =
          Source_tree.Dir.path dir
          |> Path.Build.append_source (Context_name.build_dir ctx)
          |> Path.build
        in
        Action_builder.of_memo @@ Load_rules.load_dir ~dir)
    in
    let hints =
      let candidates =
        List.fold_left load_dir ~init:Alias.Name.Map.empty ~f:(fun acc x ->
          match (x : Load_rules.Loaded.t) with
          | Build build -> Alias.Name.Map.union ~f:(fun _ a _ -> Some a) acc build.aliases
          | _ -> acc)
        |> Alias.Name.Map.to_list_map ~f:(fun name _ -> Alias.Name.to_string name)
      in
      User_message.did_you_mean (Alias.Name.to_string name) ~candidates
    in
    User_error.raise
      ~hints
      [ Pp.textf
          "Alias %S specified on the command line is empty."
          (Alias.Name.to_string name)
      ; Pp.textf
          "It is not defined in %s or any of its descendants."
          (Path.Source.to_string_maybe_quoted src_dir)
      ]
  else Action_builder.return ()
;;

let request { name; recursive; dir; contexts } =
  let contexts = List.map ~f:Context.name contexts in
  (if recursive then dep_on_alias_rec_multi_contexts else dep_on_alias_multi_contexts)
    ~dir
    ~name
    ~contexts
;;
