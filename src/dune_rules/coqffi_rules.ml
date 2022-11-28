open Import
open Memo.O

let drop_rules f =
  let+ res, _ =
    Memo.Implicit_output.collect Dune_engine.Rules.implicit_output f
  in
  res

let mod_deps ~sctx ~loc ~dir ~library ~modules ~ml_sources m =
  (* TODO: make sure deps are in the list of modules *)
  ignore modules;
  Action_builder.of_memo_join @@ drop_rules
  @@ fun () ->
  let* lib = Coqffi_sources.lib ~dir ~library in
  let* modules, locality =
    Coqffi_sources.modules_of_lib ~loc ~lib ~ml_sources
  in
  match locality with
  | `Local ->
    let+ deps =
      let local_lib =
        match Lib.Local.of_lib lib with
        | Some local -> Lib.Local.info local
        | None ->
          Code_error.raise "coqffi: external library in ocamldep modules data"
            []
      in
      let dir = Lib_info.src_dir local_lib in
      let obj_dir =
        Lib_name.to_local (loc, Lib.name lib) |> function
        | Ok local ->
          Obj_dir.make_lib ~dir ~has_private_modules:false ~private_lib:false
            local
        | Error _ ->
          Code_error.raise "coqffi: lib_name couldn't be made local" []
      in
      let modules_data : Ocamldep.Modules_data.t =
        { dir
        ; obj_dir : Path.Build.t Obj_dir.t
        ; sctx
        ; vimpl = None
        ; modules : Modules.t
        ; stdlib = None
        ; sandbox = Sandbox_config.default
        }
      in
      Dep_rules.for_module modules_data m
    in
    Ml_kind.Dict.get deps Ml_kind.Impl
  | `External -> assert false

let setup_ffi_rules ~sctx ~dir
    ({ loc; modules; library; flags } : Coqffi_stanza.t) =
  let* coqffi =
    Super_context.resolve_program ~dir sctx "coqffi" ~loc:(Some loc)
      ~hint:"opam install coq-coqffi"
  in
  let* lib = Coqffi_sources.lib ~dir ~library in
  let ml_sources = Dir_contents.get sctx ~dir >>= Dir_contents.ocaml in
  let rule (m : Module.t) =
    let stanza_flags =
      Ordered_set_lang.eval flags ~eq:( = ) ~standard:[]
        ~parse:(fun ~loc:_ flag -> Command.Args.A flag)
    in
    let mod_flags =
      let open Action_builder.O in
      let+ mod_deps =
        mod_deps ~sctx ~loc ~dir ~library ~modules ~ml_sources m
      in
      Command.Args.S
        (List.rev_map mod_deps ~f:(fun m ->
             Command.Args.S
               [ Command.Args.A "-I"
               ; Path
                   (Path.build
                   @@ Coqffi_sources.target_of ~kind:`Ffi ~dir (Module.name m))
               ]))
    in
    let args =
      [ Command.Args.Dep
          (Obj_dir.Module.cm_file_exn
             (Lib_info.obj_dir (Lib.info lib))
             ~kind:(Ocaml Cmi) m)
      ; A "--witness"
      ; Hidden_targets
          [ Coqffi_sources.target_of ~kind:`Ffi ~dir (Module.name m) ]
      ; A "-o"
      ; Target (Coqffi_sources.target_of ~kind:`V ~dir (Module.name m))
      ; S stanza_flags
      ; Dyn mod_flags
      ]
    in
    Command.run ~dir:(Path.build dir) coqffi args
  in
  let* modules =
    Coqffi_sources.modules_of ~loc ~dir ~library ~modules ~ml_sources
  in
  Super_context.add_rules ~loc ~dir sctx @@ List.rev_map ~f:rule modules
