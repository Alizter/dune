open Import

let () = Inline_tests.linkme

type build_system =
  { contexts : Context.t list
  ; scontexts : Super_context.t Context_name.Map.t
  }

let implicit_default_alias dir =
  match Path.Build.extract_build_context dir with
  | None -> Memo.return None
  | Some (ctx, src_dir) ->
    let open Memo.O in
    let context_name = Context_name.of_string (Filename.to_string ctx) in
    let* source_tree = Source_tree.for_context context_name in
    Source_tree.find_dir source_tree src_dir
    >>| (function
     | None -> None
     | Some src_dir ->
       let default_alias =
         let dune_version =
           Source_tree.Dir.project src_dir |> Dune_project.dune_version
         in
         if dune_version >= (2, 0) then Alias0.all else Alias0.install
       in
       Some (Action_builder.ignore (Alias_rec.dep_on_alias_rec default_alias dir)))
;;

let execution_parameters ~sandbox_actions =
  let source_backed_dir path =
    match Dpath.Target_dir.of_target path with
    | Regular (With_context (context, source))
    | Anonymous_action (With_context (context, source)) ->
      (match Install.Context.analyze_path context source with
       | Normal (_, source) -> Some source
       | Install _ | Invalid -> None)
    | Regular Root | Anonymous_action Root | Invalid _ -> None
  in
  let f context path =
    let open Memo.O in
    let* ep = Execution_parameters.default in
    let ep =
      if sandbox_actions then Execution_parameters.set_sandbox_actions true ep else ep
    in
    if
      Context_name.equal context Private_context.t.name
      || Context_name.equal context Fetch_rules.context.name
    then Memo.return ep
    else (
      match source_backed_dir path with
      | None -> Memo.return ep
      | Some path ->
        let* source_tree = Source_tree.for_context context in
        let+ dir = Source_tree.nearest_dir source_tree path in
        Dune_project.update_execution_parameters (Source_tree.Dir.project dir) ep)
  in
  let memo =
    let module Input = struct
      type t = Context_name.t * Path.Build.t

      let hash = Tuple.T2.hash Context_name.hash Path.Build.hash
      let equal = Tuple.T2.equal Context_name.equal Path.Build.equal
      let to_dyn = Tuple.T2.to_dyn Context_name.to_dyn Path.Build.to_dyn
    end
    in
    Memo.create
      "execution-parameters-of-dir"
      ~input:(module Input)
      ~cutoff:Execution_parameters.equal
      (fun (ctx, path) -> f ctx path)
  in
  fun context ~dir -> Memo.exec memo (context, dir)
;;

let init ~sandbox_actions ~sandboxing_preference () : unit =
  let promote_source ~chmod ~delete_dst_if_it_is_a_directory ~src ~dst =
    let open Fiber.O in
    let* ctx = Path.Build.parent_exn src |> Context.DB.by_dir |> Memo.run in
    let* source_tree = Memo.run (Source_tree.for_context (Context.name ctx)) in
    if Source_tree.read_only source_tree
    then
      User_error.raise
        [ Pp.textf
            "Cannot promote %s into a read-only source tree."
            (Path.Build.to_string_maybe_quoted src)
        ; Pp.textf
            "Context %S is backed by a read-only source (e.g. a VCS revision under [dune \
             build -r]); promotion would either silently write to the workspace's \
             working tree or fail."
            (Context_name.to_string (Context.name ctx))
        ];
    let conf = Artifact_substitution.Conf.of_context ctx in
    let src = Path.build src in
    let dst = Path.source dst in
    Artifact_substitution.copy_file
      ~chmod
      ~delete_dst_if_it_is_a_directory
      ~src
      ~dst
      ~conf
      ()
  in
  let workspace_build_contexts =
    Memo.lazy_ (fun () ->
      let open Memo.O in
      Workspace.workspace () >>| Workspace.build_contexts)
  in
  let contexts =
    Memo.lazy_ (fun () ->
      let open Memo.O in
      let+ contexts = Memo.Lazy.force workspace_build_contexts in
      let open Dune_engine.Build_config.Context_type in
      (Private_context.t, Empty)
      :: (Install.Context.install_context, Empty)
      :: (Fetch_rules.context, Empty)
      :: List.map contexts ~f:(fun (ctx, _source) -> ctx, With_sources))
  in
  let module_of_source_tree (t : Source_tree.t)
    : (module Dune_engine.Build_config.Source_tree)
    =
    (module struct
      module Dir = Source_tree.Dir

      let find_dir p = Source_tree.find_dir t p
    end)
  in
  let source_tree_of_context =
    Memo.lazy_ (fun () ->
      let open Memo.O in
      let+ contexts = Memo.Lazy.force workspace_build_contexts in
      (* Mounts of the same external path share a single [Source_tree.t]
         across toolchain variants, so [Source_resolver] identity (and
         memo caches) stay consistent. *)
      let mount_trees =
        List.fold_left
          contexts
          ~init:Path.External.Map.empty
          ~f:(fun acc ((_ctx : Build_context.t), source) ->
            match (source : Workspace.Build_context_source.t) with
            | Workspace | Vcs_rev _ -> acc
            | Mount path ->
              if Path.External.Map.mem acc path
              then acc
              else
                Path.External.Map.set
                  acc
                  path
                  (Source_tree.of_external_root ~read_only:false path))
      in
      Context_name.Map.of_list_map_exn
        contexts
        ~f:(fun ((ctx : Build_context.t), source) ->
          let tree =
            match (source : Workspace.Build_context_source.t) with
            | Workspace -> Source_tree.default
            | Mount path -> Path.External.Map.find_exn mount_trees path
            | Vcs_rev vcs_tree -> Source_tree.of_vcs_tree vcs_tree
          in
          ctx.name, tree))
  in
  Source_tree.set_for_context_callback (fun ctx ->
    let open Memo.O in
    let+ map = Memo.Lazy.force source_tree_of_context in
    match Context_name.Map.find map ctx with
    | Some t -> t
    | None -> Source_tree.default);
  let source_trees =
    Memo.lazy_ (fun () ->
      let open Memo.O in
      let+ map = Memo.Lazy.force source_tree_of_context in
      Context_name.Map.map map ~f:module_of_source_tree)
  in
  Build_config.set
    ~sandboxing_preference
    ~promote_source
    ~contexts
    ~rule_generator:(module Gen_rules)
    ~implicit_default_alias
    ~execution_parameters:(execution_parameters ~sandbox_actions)
    ~source_trees
;;

let get () =
  let open Memo.O in
  let* contexts = Context.DB.all () in
  let* scontexts = Memo.Lazy.force Super_context.all in
  let* () = Super_context.all_init_deferred () in
  Memo.return { contexts; scontexts }
;;

let find_context_exn t ~name =
  match List.find t.contexts ~f:(fun c -> Context_name.equal (Context.name c) name) with
  | Some ctx -> ctx
  | None ->
    User_error.raise [ Pp.textf "Context %S not found!" (Context_name.to_string name) ]
;;

let find_scontext_exn t ~name =
  match Context_name.Map.find t.scontexts name with
  | Some ctx -> ctx
  | None ->
    User_error.raise [ Pp.textf "Context %S not found!" (Context_name.to_string name) ]
;;
