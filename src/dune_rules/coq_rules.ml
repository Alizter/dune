open Import
open Memo.O

(* This file is licensed under The MIT License *)
(* (c) MINES ParisTech 2018-2019               *)
(* (c) INRIA 2020                              *)
(* Written by: Emilio Jesús Gallego Arias *)
(* Written by: Rudi Grinberg *)

open Coq_stanza

let deps_kind = `Coqmod

module Require_map_db = struct
  (* merge all the maps *)
  let impl (requires, buildable_map) =
    Memo.return @@ Coq_require_map.merge_all (buildable_map :: requires)

  let memo =
    let module Input = struct
      type t =
        Coq_module.t Coq_require_map.t list * Coq_module.t Coq_require_map.t

      let equal = ( == )

      let hash = Poly.hash

      let to_dyn = Dyn.opaque
    end in
    Memo.create "coq-require-map-db" ~input:(module Input) impl

  let exec ~requires map = Memo.exec memo (requires, map)
end

module Coq_plugin = struct
  let meta_info ~coq_lang_version ~plugin_loc ~context (lib : Lib.t) =
    let debug = false in
    let name = Lib.name lib |> Lib_name.to_string in
    if debug then Format.eprintf "Meta info for %s@\n" name;
    match Lib_info.status (Lib.info lib) with
    | Public (_, pkg) ->
      let package = Package.name pkg in
      let meta_i =
        Path.Build.relative
          (Local_install_path.lib_dir ~context ~package)
          "META"
      in
      if debug then
        Format.eprintf "Meta for %s: %s@\n" name (Path.Build.to_string meta_i);
      Some (Path.build meta_i)
    | Installed -> None
    | Installed_private | Private _ ->
      let is_error = coq_lang_version >= (0, 6) in
      let text = if is_error then "not supported" else "deprecated" in
      User_warning.emit ?loc:plugin_loc ~is_error
        [ Pp.textf "Using private library %s as a Coq plugin is %s" name text ];
      None

  (* compute include flags and mlpack rules *)
  let setup_ml_deps ~coq_lang_version ~context ~plugin_loc libs theories =
    (* Pair of include flags and paths to mlpack *)
    let libs =
      let open Resolve.Memo.O in
      let* theories = theories in
      let* theories =
        Resolve.Memo.lift
        @@ Resolve.List.concat_map ~f:Coq_lib.libraries theories
      in
      let libs = libs @ theories in
      Lib.closure ~linking:false (List.map ~f:snd libs)
    in
    let flags =
      Resolve.Memo.args
        (Resolve.Memo.map libs ~f:(fun libs ->
             Path.Set.of_list_map libs ~f:(fun t ->
                 let info = Lib.info t in
                 Lib_info.src_dir info)
             |> Lib_flags.L.to_iflags))
    in
    let open Action_builder.O in
    ( flags
    , let* libs = Resolve.Memo.read libs in
      (* coqdep expects an mlpack file next to the sources otherwise it will
         omit the cmxs deps *)
      let ml_pack_files lib =
        let plugins =
          let info = Lib.info lib in
          let plugins = Lib_info.plugins info in
          Mode.Dict.get plugins Native
        in
        let to_mlpack file =
          [ Path.set_extension file ~ext:".mlpack"
          ; Path.set_extension file ~ext:".mllib"
          ]
        in
        List.concat_map plugins ~f:to_mlpack
      in
      (* If the mlpack files don't exist, don't fail *)
      Action_builder.all_unit
        [ Action_builder.paths
            (List.filter_map
               ~f:(meta_info ~plugin_loc ~coq_lang_version ~context)
               libs)
        ; Action_builder.paths_existing (List.concat_map ~f:ml_pack_files libs)
        ] )

  let of_buildable ~context ~lib_db ~theories_deps
      (buildable : Coq_stanza.Buildable.t) =
    let res =
      let open Resolve.Memo.O in
      let+ libs =
        Resolve.Memo.List.map buildable.plugins ~f:(fun (loc, name) ->
            let+ lib = Lib.DB.resolve lib_db (loc, name) in
            (loc, lib))
      in
      let coq_lang_version = buildable.coq_lang_version in
      let plugin_loc = List.hd_opt buildable.plugins |> Option.map ~f:fst in
      setup_ml_deps ~plugin_loc ~coq_lang_version ~context libs theories_deps
    in
    let ml_flags = Resolve.Memo.map res ~f:fst in
    let mlpack_rule =
      let open Action_builder.O in
      let* _, mlpack_rule = Resolve.Memo.read res in
      mlpack_rule
    in
    (ml_flags, mlpack_rule)
end

module Bootstrap = struct
  (* the internal boot flag determines if the Coq "standard library" is being
     built, in case we need to explicitly tell Coq where the build artifacts are
     and add `Init.Prelude.vo` as a dependency; there is a further special case
     when compiling the prelude, in this case we also need to tell Coq not to
     try to load the prelude. *)
  type t =
    | No_boot  (** Coq's stdlib is installed globally *)
    | Bootstrap of Coq_lib.t
        (** Coq's stdlib is in scope of the composed build *)
    | Bootstrap_prelude
        (** We are compiling the prelude itself
            [should be replaced with (per_file ...) flags] *)

  let get ~use_stdlib ~boot_lib ~wrapper_name coq_module =
    if use_stdlib then
      match boot_lib with
      | None -> No_boot
      | Some (_loc, lib) ->
        (* This is here as an optimization, TODO; replace with per_file flags *)
        let init =
          let open Coq_module in
          String.equal (Coq_lib_name.wrapper (Coq_lib.name lib)) wrapper_name
          && Path.is_prefix (prefix coq_module)
               ~prefix:(Path.of_string_list [ "Init" ])
        in
        if init then Bootstrap_prelude else Bootstrap lib
    else Bootstrap_prelude

  let flags ~coqdoc t : _ Command.Args.t =
    match t with
    | No_boot -> Command.Args.empty
    | Bootstrap lib ->
      if coqdoc then
        S [ A "--coqlib"; Path (Path.build @@ Coq_lib.src_root lib) ]
      else A "-boot"
    | Bootstrap_prelude -> As [ "-boot"; "-noinit" ]
end

let coqc ~loc ~dir ~sctx =
  Super_context.resolve_program sctx "coqc" ~dir ~loc:(Some loc)
    ~hint:"opam install coq"

let select_native_mode ~sctx ~dir (buildable : Coq_stanza.Buildable.t) =
  match buildable.mode with
  | Some x ->
    if
      buildable.coq_lang_version < (0, 7)
      && Profile.is_dev (Super_context.context sctx).profile
    then Memo.return Coq_mode.VoOnly
    else Memo.return x
  | None -> (
    if buildable.coq_lang_version < (0, 3) then Memo.return Coq_mode.Legacy
    else if buildable.coq_lang_version < (0, 7) then Memo.return Coq_mode.VoOnly
    else
      let* coqc = coqc ~sctx ~dir ~loc:buildable.loc in
      let+ config = Coq_config.make ~bin:(Action.Prog.ok_exn coqc) in
      match Coq_config.by_name config "coq_native_compiler_default" with
      | Some (`String "yes") | Some (`String "ondemand") -> Coq_mode.Native
      | _ -> Coq_mode.VoOnly)

let coq_flags ~dir ~stanza_flags ~expander ~sctx =
  let open Action_builder.O in
  let* standard = Action_builder.of_memo @@ Super_context.coq ~dir sctx in
  Expander.expand_and_eval_set expander stanza_flags ~standard

let boot_type ~dir ~use_stdlib ~wrapper_name coq_module =
  let open Action_builder.O in
  let* scope = Action_builder.of_memo @@ Scope.DB.find_by_dir dir in
  let+ boot_lib =
    scope |> Scope.coq_libs |> Coq_lib.DB.boot_library |> Resolve.Memo.read
  in
  Bootstrap.get ~use_stdlib ~boot_lib ~wrapper_name coq_module

module Context = struct
  type 'a t =
    { mlpack_rule : unit Action_builder.t
    ; ml_flags : 'a Command.Args.t Resolve.Memo.t
    ; native_includes : Path.Set.t Resolve.t
    ; native_theory_includes : Path.Build.Set.t Resolve.t
    }

  let theories_flags ~theories_deps =
    let theory_coqc_flag lib =
      let dir = Coq_lib.src_root lib in
      let binding_flag = if Coq_lib.implicit lib then "-R" else "-Q" in
      Command.Args.S
        [ A binding_flag
        ; Path (Path.build dir)
        ; A (Coq_lib.name lib |> Coq_lib_name.wrapper)
        ]
    in
    Resolve.Memo.args
      (let open Resolve.Memo.O in
      let+ libs = theories_deps in
      Command.Args.S (List.map ~f:theory_coqc_flag libs))

  let coqc_file_flags ~dir ~theories_deps ~wrapper_name ~use_stdlib cctx
      coq_module =
    let file_flags : _ Command.Args.t list =
      [ Dyn (Resolve.Memo.read cctx.ml_flags)
      ; theories_flags ~theories_deps
      ; A "-R"
      ; Path (Path.build dir)
      ; A wrapper_name
      ]
    in
    ([ Dyn
         (Action_builder.map
            ~f:(fun b -> Bootstrap.flags ~coqdoc:false b)
            (boot_type ~dir ~use_stdlib ~wrapper_name coq_module))
     ; S file_flags
     ]
      : _ Command.Args.t list)

  let coqc_native_flags ~(mode : Coq_mode.t) cctx : _ Command.Args.t =
    match mode with
    | Legacy -> Command.Args.As []
    | VoOnly ->
      As
        [ "-w"
        ; "-deprecated-native-compiler-option"
        ; "-w"
        ; "-native-compiler-disabled"
        ; "-native-compiler"
        ; "ondemand"
        ]
    | Native | Native_split ->
      let args =
        let open Resolve.O in
        let* native_includes = cctx.native_includes in
        let include_ dir acc = Command.Args.Path dir :: A "-nI" :: acc in
        let native_include_ml_args =
          Path.Set.fold native_includes ~init:[] ~f:include_
        in
        let+ native_theory_includes = cctx.native_theory_includes in
        let native_include_theory_output =
          Path.Build.Set.fold native_theory_includes ~init:[] ~f:(fun dir acc ->
              include_ (Path.build dir) acc)
        in
        let options =
          match mode with
          | Native ->
            [ Command.Args.As [ "-w"; "-deprecated-native-compiler-option" ]
            ; As [ "-native-output-dir"; "." ]
            ; As [ "-native-compiler"; "on" ]
            ]
          | Native_split -> [ Command.Args.As [ "-native-output-dir"; "." ] ]
          | _ -> []
        in
        (* This dir is relative to the file, by default [.coq-native/] *)
        Command.Args.S
          [ S options
          ; S (List.rev native_include_ml_args)
          ; S (List.rev native_include_theory_output)
          ]
      in
      Resolve.args args

  let directories_of_lib ~sctx lib =
    let name = Coq_lib.name lib in
    let dir = Coq_lib.src_root lib in
    let* dir_contents = Dir_contents.get sctx ~dir in
    let+ coq_sources = Dir_contents.coq dir_contents in
    Coq_sources.directories coq_sources ~name

  let native_includes ~dir =
    let* scope = Scope.DB.find_by_dir dir in
    let lib_db = Scope.libs scope in
    let rec resolve_first lib_db = function
      | [] -> assert false
      | [ n ] -> Lib.DB.resolve lib_db (Loc.none, Lib_name.of_string n)
      | n :: l -> (
        let open Memo.O in
        Lib.DB.resolve_when_exists lib_db (Loc.none, Lib_name.of_string n)
        >>= function
        | Some l -> Resolve.Memo.lift l
        | None -> resolve_first lib_db l)
    in
    (* We want the cmi files *)
    Resolve.Memo.map ~f:(fun lib ->
        let info = Lib.info lib in
        let obj_dir = Obj_dir.public_cmi_ocaml_dir (Lib_info.obj_dir info) in
        Path.Set.singleton obj_dir)
    @@ resolve_first lib_db [ "coq-core.kernel"; "coq.kernel" ]

  let setup_native_theory_includes ~sctx ~dir ~theories_deps ~theory_dirs
      buildable =
    let* mode = select_native_mode ~sctx ~dir buildable in
    match (mode : Coq_mode.t) with
    | VoOnly | Legacy -> Resolve.Memo.return Path.Build.Set.empty
    | Native | Native_split ->
      Resolve.Memo.bind theories_deps ~f:(fun theories_deps ->
          let+ l =
            Memo.parallel_map theories_deps ~f:(fun lib ->
                let+ theory_dirs = directories_of_lib ~sctx lib in
                Path.Build.Set.of_list theory_dirs)
          in
          Resolve.return (Path.Build.Set.union_all (theory_dirs :: l)))

  let create sctx ~dir ~theories_deps ~theory_dirs stanza =
    let buildable =
      match stanza with
      | `Extraction (e : Extraction.t) -> e.buildable
      | `Theory (t : Theory.t) -> t.buildable
    in
    let context = Super_context.context sctx |> Context.name in
    let* scope = Scope.DB.find_by_dir dir in
    let lib_db = Scope.libs scope in
    (* ML-level flags for depending libraries *)
    let ml_flags, mlpack_rule =
      Coq_plugin.of_buildable ~context ~theories_deps ~lib_db buildable
    in
    let* native_includes = native_includes ~dir in
    let+ native_theory_includes =
      setup_native_theory_includes ~sctx ~dir ~theories_deps ~theory_dirs
        buildable
    in
    { mlpack_rule; ml_flags; native_includes; native_theory_includes }
end

let theories_deps_requires_for_user_written ~dir
    (buildable : Coq_stanza.Buildable.t) =
  let open Memo.O in
  let* scope = Scope.DB.find_by_dir dir in
  let coq_lib_db = Scope.coq_libs scope in
  Coq_lib.DB.requires_for_user_written coq_lib_db buildable.theories
    ~coq_lang_version:buildable.coq_lang_version

let parse_coqdep ~dir ~(boot_type : Bootstrap.t) ~coq_module
    (lines : string list) =
  let source = Coq_module.source coq_module in
  let invalid phase =
    User_error.raise
      [ Pp.textf "coqdep returned invalid output for %s / [phase: %s]"
          (Path.Build.to_string_maybe_quoted source)
          phase
      ; Pp.verbatim (String.concat ~sep:"\n" lines)
      ]
  in
  let line =
    match lines with
    | [] | _ :: _ :: _ :: _ -> invalid "line"
    | [ line ] -> line
    | [ l1; _l2 ] ->
      (* .vo is produced before .vio, this is fragile tho *)
      l1
  in
  match String.lsplit2 line ~on:':' with
  | None -> invalid "split"
  | Some (basename, deps) -> (
    let ff = List.hd @@ String.extract_blank_separated_words basename in
    let depname, _ = Filename.split_extension ff in
    let modname =
      let name = Coq_module.name coq_module in
      let prefix = Coq_module.prefix coq_module in
      let path = Coq_module.Path.append_name prefix name in
      String.concat ~sep:"/" (Coq_module.Path.to_string_list path)
    in
    if depname <> modname then invalid "basename";
    let deps = String.extract_blank_separated_words deps in
    (* Add prelude deps for when stdlib is in scope and we are not actually
       compiling the prelude *)
    let deps = List.map ~f:(Path.relative (Path.build dir)) deps in
    match boot_type with
    | No_boot | Bootstrap_prelude -> deps
    | Bootstrap lib ->
      Path.relative (Path.build (Coq_lib.src_root lib)) "Init/Prelude.vo"
      :: deps)

let _debug = false
(* DEBUG *)

let err_from_not_found ~loc from source =
  User_error.raise ~loc
  @@ (match Coqmod.From.prefix from with
     | Some prefix ->
       [ Pp.textf "could not find module %S with prefix %S"
           (Coqmod.From.require from |> Coqmod.Module.name)
           (prefix |> Coqmod.Module.name)
       ]
     | None ->
       [ Pp.textf "could not find module %S."
           (Coqmod.From.require from |> Coqmod.Module.name)
       ])
  @
  if _debug then
    [ Pp.textf "%s\n" @@ Dyn.to_string @@ Coq_require_map.to_dyn source ]
  else []

let err_from_ambiguous ~loc m _from source =
  User_error.raise ~loc
  @@ [ Pp.textf "TODO ambiguous paths:\n%s\n"
       @@ Dyn.to_string
       @@ Dyn.list Coq_module.to_dyn m
     ]
  @
  if _debug then
    [ Pp.textf "%s" @@ Dyn.to_string @@ Coq_require_map.to_dyn source ]
  else []

let err_undeclared_plugin ~loc libname =
  User_error.raise ~loc
    Pp.[ textf "TODO undelcared plugin %S" (Lib_name.to_string libname) ]

let coq_require_map_of_theory ~sctx lib =
  let name = Coq_lib.name lib in
  let dir = Coq_lib.src_root lib in
  let* dir_contents = Dir_contents.get sctx ~dir in
  let+ coq_sources = Dir_contents.coq dir_contents in
  Coq_sources.require_map ~skip_theory_prefix:false coq_sources (`Theory name)

module Deps = struct
  let loc from_ coq_module =
    let fname = Coq_module.source coq_module |> Path.Build.to_string in
    Coqmod.From.require from_ |> Coqmod.Module.loc |> Coqmod.Loc.to_loc ~fname

  let froms ~theories ~theory_rms ~sources ~coq_module t =
    let f (from_ : Coqmod.From.t) =
      let loc = loc from_ coq_module in
      let prefix =
        Option.map (Coqmod.From.prefix from_) ~f:(fun p ->
            Coq_module.Path.of_string @@ Coqmod.Module.name p)
      in
      let suffix =
        Coqmod.From.require from_ |> Coqmod.Module.name
        |> Coq_module.Path.of_string
      in
      let open Memo.O in
      let+ require_map =
        let theories =
          match prefix with
          | Some prefix ->
            List.filter theories ~f:(fun theory ->
                Coq_module.Path.is_prefix ~prefix @@ Coq_lib.root_path theory)
          | None ->
            (* TODO this is incorrect, needs to include only current theory
               and boot library if present *)
            theories
        in
        let requires = List.map theories ~f:(Coq_lib.Map.find_exn theory_rms) in
        if _debug then
          Printf.printf "prefix: %s\t suffix: %s\t requires: %s\n"
            (Dyn.option Coq_module.Path.to_dyn prefix |> Dyn.to_string)
            (Coq_module.Path.to_dyn suffix |> Dyn.to_string)
            (Dyn.list Coq_require_map.to_dyn requires |> Dyn.to_string);
        Require_map_db.exec ~requires sources
      in
      let matches =
        match prefix with
        | Some prefix -> Coq_require_map.find_all ~prefix ~suffix require_map
        | None ->
          Coq_require_map.find_all ~prefix:Coq_module.Path.empty ~suffix
            require_map
      in
      let disambiguate_matches =
        match matches with
        | [] -> err_from_not_found ~loc from_ require_map
        | ms -> (
          let local_debug = true in
          if local_debug then
            Printf.printf "Actual module: %s\n"
              (Coq_module.path ~skip_theory_prefix:false coq_module
              |> Coq_module.Path.to_dyn |> Dyn.to_string);
          let rate m =
            if local_debug then
              Printf.printf "%s\n" (Coq_module.Path.to_dyn m |> Dyn.to_string);
            (match prefix with
            | None -> m
            | Some prefix -> Coq_module.Path.remove_prefix ~prefix m)
            |> fun m ->
            if local_debug then
              Printf.printf "chosen m: %s\n"
                (Coq_module.Path.to_dyn m |> Dyn.to_string);
            m |> Coq_module.Path.remove_suffix ~suffix |> fun m ->
            if local_debug then
              Printf.printf "after suff: %s\n"
                (Coq_module.Path.to_dyn m |> Dyn.to_string);
            m |> Coq_module.Path.length
          in
          if local_debug then (
            Printf.printf "Found modules:\n";
            List.iter
              ~f:(fun x ->
                Coq_module.path ~skip_theory_prefix:false x
                |> Coq_module.Path.to_dyn |> Dyn.to_string
                |> Printf.printf "%s\n")
              ms);
          List.min
            ~f:(fun m1 m2 ->
              Int.compare
                (rate @@ Coq_module.path ~skip_theory_prefix:false m1)
                (rate @@ Coq_module.path ~skip_theory_prefix:false m2))
            ms
          |> function
          | None -> err_from_ambiguous ~loc ms from_ require_map
          | Some m -> m)
      in
      Path.build (Coq_module.vo_file disambiguate_matches)
    in

    Coqmod.froms t |> Memo.parallel_map ~f |> Action_builder.of_memo

  let boot_deps ~boot_type =
    let open Bootstrap in
    let open Action_builder.O in
    let+ boot_type = boot_type in
    match boot_type with
    | No_boot | Bootstrap_prelude -> []
    | Bootstrap lib ->
      [ Path.relative (Path.build (Coq_lib.src_root lib)) "Init/Prelude.vo" ]

  let loads ~dir t =
    Coqmod.loads t
    |> List.rev_map ~f:(fun file ->
           let fname = Coqmod.Load.path file in
           Path.build (Path.Build.relative dir fname))

  let extradeps t =
    Coqmod.extradeps t
    |> List.rev_map ~f:(fun file ->
           let fname = Coqmod.ExtraDep.file file in
           let path =
             Coqmod.ExtraDep.from file |> Coqmod.Module.name
             |> Dune_re.replace_string Re.(compile @@ char '.') ~by:"/"
             |> Path.Local.of_string |> Path.Build.of_local
           in
           Path.build (Path.Build.relative path fname))

  let coqmod_deps ~theories ~sources ~dir ~theory_rms ~boot_type coq_module =
    let open Action_builder.O in
    let* t = Coqmod_rules.deps_of coq_module in
    (* convert [Coqmod.t] to a list of paths repping the deps *)
    let+ froms = froms ~theories ~theory_rms ~sources ~coq_module t
    and+ boot_deps = boot_deps ~boot_type in
    (* Add prelude deps for when stdlib is in scope and we are not actually
       compiling the prelude *)
    (* TODO: plugin deps *)
    ignore err_undeclared_plugin;
    List.concat [ froms; loads ~dir t; extradeps t; boot_deps ]

  let of_ ~sctx ~theories ~stanza ~dir ~boot_type coq_module =
    Memo.return
    @@
    let open Action_builder.O in
    match deps_kind with
    | `Coqmod ->
      let* sources =
        Action_builder.of_memo
        @@
        let open Memo.O in
        let* dir_contents = Dir_contents.get sctx ~dir in
        let+ coq_sources = Dir_contents.coq dir_contents in
        let what =
          match stanza with
          | `Extraction e -> `Extraction e
          | `Theory (t : Theory.t) -> `Theory (snd t.name)
        in
        match stanza with
        | `Extraction _ ->
          Coq_sources.require_map ~skip_theory_prefix:true coq_sources what
        | `Theory (t : Theory.t) ->
          if t.boot then
            Coq_require_map.merge_all
              [ Coq_sources.require_map ~skip_theory_prefix:true coq_sources
                  what
              ; Coq_sources.require_map ~skip_theory_prefix:false coq_sources
                  what
              ]
          else
            Coq_sources.require_map ~skip_theory_prefix:false coq_sources what
      in
      let* theory_rms =
        Action_builder.of_memo
        @@ (Memo.parallel_map theories ~f:(fun theory ->
                let open Memo.O in
                let+ require_map = coq_require_map_of_theory ~sctx theory in
                (theory, require_map))
           |> Memo.map ~f:Coq_lib.Map.of_list_exn)
      in
      coqmod_deps ~theories ~sources ~dir ~theory_rms ~boot_type coq_module
      |> Action_builder.dyn_paths_unit
    | `Coqdep ->
      let stdout_to = Coq_module.dep_file coq_module in
      let* boot_type = boot_type in
      Action_builder.map
        (Action_builder.lines_of (Path.build stdout_to))
        ~f:(parse_coqdep ~dir ~boot_type ~coq_module)
      |> Action_builder.dyn_paths_unit
end

let coqdep_rule (cctx : _ Context.t) ~dir ~coqdep ~source_rule ~theories_deps
    ~wrapper_name ~use_stdlib coq_module =
  (* coqdep needs the full source + plugin's mlpack to be present :( *)
  let source = Coq_module.source coq_module in
  let file_flags =
    [ Command.Args.S
        (Context.coqc_file_flags cctx coq_module ~dir ~theories_deps
           ~wrapper_name ~use_stdlib)
    ; As [ "-dyndep"; "opt" ]
    ; Dep (Path.build source)
    ]
  in
  let stdout_to = Coq_module.dep_file coq_module in
  (* Coqdep has to be called in the stanza's directory *)
  let open Action_builder.With_targets.O in
  Action_builder.with_no_targets cctx.mlpack_rule
  >>> Action_builder.(with_no_targets (goal source_rule))
  >>> Command.run ~dir:(Path.build dir) ~stdout_to coqdep file_flags

let coqc_rule (cctx : _ Context.t) ~coq_flags ~deps_of ~file_flags ~coqc
    ~coqc_dir ~mode ~file_targets ~obj_files_mode ~wrapper_name coq_module =
  let open Action_builder.With_targets.O in
  Action_builder.with_no_targets deps_of
  >>> Action_builder.With_targets.add ~file_targets
      @@ Command.run ~dir:(Path.build coqc_dir) coqc
           [ Command.Args.dyn coq_flags
           ; Hidden_targets
               (Coq_module.obj_files ~wrapper_name ~mode ~obj_files_mode
                  coq_module
               |> List.map ~f:fst)
           ; Context.coqc_native_flags ~mode cctx
           ; S file_flags
           ; Dep
               (Path.build
               @@
               match mode with
               | Native_split -> Coq_module.vo_file coq_module
               | _ -> Coq_module.source coq_module)
           ]
  (* The way we handle the transitive dependencies of .vo files is not safe for
     sandboxing *)
  >>| Action.Full.add_sandbox Sandbox_config.no_sandboxing

let setup_coqc_rule ~loc ~dir ~sctx (cctx : _ Context.t) ~file_targets
    ~stanza_flags ~theories_deps ~mode ~source_rule ~wrapper_name ~use_stdlib
    ~stanza coq_module =
  (* Process coqdep and generate rules *)
  let file_flags =
    Context.coqc_file_flags ~dir ~theories_deps ~wrapper_name ~use_stdlib cctx
      coq_module
  in
  (match deps_kind with
  | `Coqmod -> Coqmod_rules.add_rule sctx coq_module
  | `Coqdep ->
    let* coqdep =
      Super_context.resolve_program sctx "coqdoc" ~dir ~loc:(Some loc)
        ~hint:"opam install coq"
    in
    let rule =
      coqdep_rule cctx ~dir ~coqdep ~source_rule ~theories_deps ~wrapper_name
        ~use_stdlib coq_module
    in
    Super_context.add_rule ~loc ~dir sctx rule)
  >>> (* Process deps and generate rules *)
  let* deps_of =
    let* theories = theories_deps in
    let* theories = Resolve.read_memo theories in
    let boot_type = boot_type ~dir ~use_stdlib ~wrapper_name coq_module in
    Deps.of_ ~sctx ~theories ~stanza ~dir ~boot_type coq_module
  in
  let* coqc = coqc ~loc ~dir ~sctx in
  let* expander = Super_context.expander sctx ~dir in
  let coq_flags = coq_flags ~dir ~stanza_flags ~expander ~sctx in
  let coqc_dir = (Super_context.context sctx).build_dir in
  match (mode : Coq_mode.t) with
  | Legacy | Native | VoOnly ->
    Super_context.add_rule ~loc ~dir sctx
      (coqc_rule cctx ~file_flags ~coqc ~coqc_dir ~coq_flags ~deps_of
         ~file_targets ~mode ~obj_files_mode:Coq_module.Build coq_module
         ~wrapper_name)
  | Native_split ->
    let* coqnative =
      Super_context.resolve_program sctx ~dir ~loc:(Some loc) "coqnative"
        ~hint:"opam install coq coq-native"
    in
    Super_context.add_rules ~loc ~dir sctx
      [ coqc_rule cctx ~file_flags ~coqc ~coqc_dir ~coq_flags ~deps_of
          ~file_targets ~mode:Coq_mode.VoOnly ~obj_files_mode:Coq_module.Build
          coq_module ~wrapper_name
      ; coqc_rule cctx ~file_flags ~coqc:coqnative ~coqc_dir
          ~coq_flags:(Action_builder.return []) ~deps_of ~file_targets
          ~mode:Coq_mode.Native_split ~obj_files_mode:Coq_module.No_obj
          ~wrapper_name coq_module
      ]

let coq_modules_of_theory ~sctx lib =
  Action_builder.of_memo
    (let name = Coq_lib.name lib in
     let dir = Coq_lib.src_root lib in
     let* dir_contents = Dir_contents.get sctx ~dir in
     let+ coq_sources = Dir_contents.coq dir_contents in
     Coq_sources.library coq_sources ~name)

let source_rule ~sctx theories =
  (* sources for depending libraries coqdep requires all the files to be in the
     tree to produce correct dependencies, including those of dependencies *)
  Action_builder.dyn_paths_unit
    (let open Action_builder.O in
    let* theories = Resolve.Memo.read theories in
    let+ l =
      Action_builder.List.map theories ~f:(coq_modules_of_theory ~sctx)
    in
    List.concat l |> List.rev_map ~f:(fun m -> Path.build (Coq_module.source m)))

let setup_cctx_and_modules ~sctx ~dir ~theories_deps ~dir_contents
    (s : Theory.t) =
  let name = snd s.name in
  let* coq_dir_contents = Dir_contents.coq dir_contents in
  let theory_dirs =
    Coq_sources.directories coq_dir_contents ~name |> Path.Build.Set.of_list
  in
  let+ cctx =
    Context.create sctx ~dir ~theories_deps ~theory_dirs (`Theory s)
  in
  let coq_modules = Coq_sources.library coq_dir_contents ~name in
  (cctx, coq_modules)

module Coqdoc_mode = struct
  type t =
    | Html
    | Latex

  let flag = function
    | Html -> "--html"
    | Latex -> "--latex"

  let directory t obj_dir (theory : Coq_lib_name.t) =
    Path.Build.relative obj_dir
      (Coq_lib_name.to_string theory
      ^
      match t with
      | Html -> ".html"
      | Latex -> ".tex")

  let alias t ~dir =
    match t with
    | Html -> Alias.doc ~dir
    | Latex -> Alias.doc_latex ~dir
end

let coqdoc_directory_targets ~dir:obj_dir (theory : Coq_stanza.Theory.t) =
  let loc = theory.buildable.loc in
  let name = snd theory.name in
  Path.Build.Map.of_list_exn
    [ (Coqdoc_mode.directory Html obj_dir name, loc)
    ; (Coqdoc_mode.directory Latex obj_dir name, loc)
    ]

let setup_coqdoc_rules ~sctx ~dir ~theories_deps ~wrapper_name (s : Theory.t)
    coq_modules =
  let loc, name = (s.buildable.loc, snd s.name) in
  let rule =
    let file_flags =
      let file_flags =
        [ Context.theories_flags ~theories_deps
        ; A "-R"
        ; Path (Path.build dir)
        ; A wrapper_name
        ]
      in
      (* BUG: we were passing No_boot before and now we have made it explicit. We
          probably want to do something better here. *)
      [ Bootstrap.flags ~coqdoc:true Bootstrap.No_boot; S file_flags ]
    in
    fun mode ->
      let* () =
        let* coqdoc =
          Super_context.resolve_program sctx "coqdoc" ~dir ~loc:(Some loc)
            ~hint:"opam install coq"
        in
        (let doc_dir = Coqdoc_mode.directory mode dir name in
         let file_flags =
           let globs =
             let open Action_builder.O in
             let* theories_deps = Resolve.Memo.read theories_deps in
             Action_builder.of_memo
             @@
             let open Memo.O in
             let+ deps =
               Memo.parallel_map theories_deps ~f:(fun theory ->
                   let+ theory_dirs = Context.directories_of_lib ~sctx theory in
                   Dep.Set.of_list_map theory_dirs ~f:(fun dir ->
                       (* TODO *)
                       Glob.of_string_exn Loc.none "*.glob"
                       |> File_selector.of_glob ~dir:(Path.build dir)
                       |> Dep.file_selector))
             in
             Command.Args.Hidden_deps (Dep.Set.union_all deps)
           in
           [ Command.Args.S file_flags
           ; A "--toc"
           ; A Coqdoc_mode.(flag mode)
           ; A "-d"
           ; Path (Path.build doc_dir)
           ; Deps
               (List.map ~f:Path.build
               @@ List.map ~f:Coq_module.source coq_modules)
           ; Dyn globs
           ; Hidden_deps
               (Dep.Set.of_files @@ List.map ~f:Path.build
               @@ List.map ~f:Coq_module.glob_file coq_modules)
           ]
         in
         Command.run ~sandbox:Sandbox_config.needs_sandboxing
           ~dir:(Path.build dir) coqdoc file_flags
         |> Action_builder.With_targets.map
              ~f:
                (Action.Full.map ~f:(fun coqdoc ->
                     Action.Progn [ Action.mkdir doc_dir; coqdoc ]))
         |> Action_builder.With_targets.add_directories
              ~directory_targets:[ doc_dir ])
        |> Super_context.add_rule ~loc ~dir sctx
      in
      Coqdoc_mode.directory mode dir name
      |> Path.build |> Action_builder.path
      |> Rules.Produce.Alias.add_deps (Coqdoc_mode.alias mode ~dir) ~loc
  in
  rule Html >>> rule Latex

let setup_theory_rules ~sctx ~dir ~dir_contents (s : Theory.t) =
  let theory =
    let* scope = Scope.DB.find_by_dir dir in
    let coq_lib_db = Scope.coq_libs scope in
    Coq_lib.DB.resolve coq_lib_db ~coq_lang_version:s.buildable.coq_lang_version
      s.name
  in
  let theories_deps =
    Resolve.Memo.bind theory ~f:(fun theory ->
        Resolve.Memo.lift @@ Coq_lib.theories_closure theory)
  in
  let wrapper_name = Coq_lib_name.wrapper (snd s.name) in
  let* cctx, coq_modules =
    setup_cctx_and_modules ~sctx ~dir ~dir_contents ~theories_deps s
  in
  let loc = s.buildable.loc in
  let source_rule =
    let theories =
      let open Resolve.Memo.O in
      let+ theory = theory
      and+ theories = theories_deps in
      theory :: theories
    in
    source_rule ~sctx theories
  in
  let* mode = select_native_mode ~sctx ~dir s.buildable in
  Memo.parallel_iter coq_modules
    ~f:
      (setup_coqc_rule ~sctx ~loc cctx ~source_rule ~dir ~file_targets:[]
         ~theories_deps ~stanza_flags:s.buildable.flags
         ~use_stdlib:s.buildable.use_stdlib ~mode ~wrapper_name
         ~stanza:(`Theory s))
  >>> setup_coqdoc_rules ~sctx ~dir ~theories_deps s coq_modules ~wrapper_name

let coqtop_args_theory ~sctx ~dir ~dir_contents (s : Theory.t) coq_module =
  let theories_deps =
    theories_deps_requires_for_user_written ~dir s.buildable
  in
  let wrapper_name = Coq_lib_name.wrapper (snd s.name) in
  let open Action_builder.O in
  let* cctx, _ =
    Action_builder.of_memo
    @@ setup_cctx_and_modules ~sctx ~dir ~dir_contents ~theories_deps s
  in
  let* expander = Action_builder.of_memo @@ Super_context.expander sctx ~dir in
  let* mode =
    Action_builder.of_memo @@ select_native_mode ~sctx ~dir s.buildable
  in
  let+ coq_flags =
    coq_flags ~expander ~dir ~stanza_flags:s.buildable.flags ~sctx
  in
  Command.Args.As coq_flags
  :: Command.Args.S [ Context.coqc_native_flags ~mode cctx ]
  :: Context.coqc_file_flags ~dir ~theories_deps ~wrapper_name
       ~use_stdlib:s.buildable.use_stdlib cctx coq_module

(******************************************************************************)
(* Install rules *)
(******************************************************************************)

(* This is here for compatibility with Coq < 8.11, which expects plugin files to
   be in the folder containing the `.vo` files *)
let coq_plugins_install_rules ~scope ~package ~dst_dir (s : Theory.t) =
  let lib_db = Scope.libs scope in
  let+ ml_libs =
    (* get_libraries from Coq's ML dependencies *)
    Resolve.Memo.read_memo
      (Resolve.Memo.List.map ~f:(Lib.DB.resolve lib_db) s.buildable.plugins)
  in
  let rules_for_lib lib =
    let info = Lib.info lib in
    (* Don't install libraries that don't belong to this package *)
    if
      let name = Package.name package in
      Option.equal Package.Name.equal (Lib_info.package info) (Some name)
    then
      let loc = Lib_info.loc info in
      let plugins = Lib_info.plugins info in
      Mode.Dict.get plugins Native
      |> List.map ~f:(fun plugin_file ->
             (* Safe because all coq libraries are local for now *)
             let plugin_file = Path.as_in_build_dir_exn plugin_file in
             let plugin_file_basename = Path.Build.basename plugin_file in
             let dst =
               Path.Local.(to_string (relative dst_dir plugin_file_basename))
             in
             let entry =
               (* TODO this [loc] should come from [s.buildable.libraries] *)
               Install.Entry.make Section.Lib_root ~dst ~kind:`File plugin_file
             in
             Install.Entry.Sourced.create ~loc entry)
    else []
  in
  List.concat_map ~f:rules_for_lib ml_libs

let install_rules ~sctx ~dir s =
  match s with
  | { Theory.package = None; _ } -> Memo.return []
  | { Theory.package = Some package; buildable; _ } ->
    let loc = s.buildable.loc in
    let* mode = select_native_mode ~sctx ~dir buildable in
    let* scope = Scope.DB.find_by_dir dir in
    let* dir_contents = Dir_contents.get sctx ~dir in
    let name = snd s.name in
    (* This must match the wrapper prefix for now to remain compatible *)
    let dst_suffix = Coq_lib_name.dir name in
    (* These are the rules for now, coq lang 2.0 will make this uniform *)
    let dst_dir =
      if s.boot then
        (* We drop the "Coq" prefix (!) *)
        Path.Local.of_string "coq/theories"
      else
        let coq_root = Path.Local.of_string "coq/user-contrib" in
        Path.Local.relative coq_root dst_suffix
    in
    (* Also, stdlib plugins are handled in a hardcoded way, so no compat install
       is needed *)
    let* coq_plugins_install_rules =
      if s.boot then Memo.return []
      else coq_plugins_install_rules ~scope ~package ~dst_dir s
    in
    let wrapper_name = Coq_lib_name.wrapper name in
    let to_path f = Path.reach ~from:(Path.build dir) (Path.build f) in
    let to_dst f = Path.Local.to_string @@ Path.Local.relative dst_dir f in
    let make_entry (orig_file : Path.Build.t) (dst_file : string) =
      let entry =
        Install.Entry.make Section.Lib_root ~dst:(to_dst dst_file) orig_file
          ~kind:`File
      in
      Install.Entry.Sourced.create ~loc entry
    in
    let+ coq_sources = Dir_contents.coq dir_contents in
    coq_sources |> Coq_sources.library ~name
    |> List.concat_map ~f:(fun (vfile : Coq_module.t) ->
           let obj_files =
             Coq_module.obj_files ~wrapper_name ~mode
               ~obj_files_mode:Coq_module.Install vfile
             |> List.map
                  ~f:(fun ((vo_file : Path.Build.t), (install_vo_file : string))
                     -> make_entry vo_file install_vo_file)
           in
           let vfile = Coq_module.source vfile in
           let vfile_dst = to_path vfile in
           make_entry vfile vfile_dst :: obj_files)
    |> List.rev_append coq_plugins_install_rules

let setup_coqpp_rules ~sctx ~dir ({ loc; modules } : Coqpp.t) =
  let* coqpp =
    Super_context.resolve_program sctx "coqpp" ~dir ~loc:(Some loc)
      ~hint:"opam install coq"
  and* mlg_files = Coq_sources.mlg_files ~sctx ~dir ~modules in
  let mlg_rule m =
    let source = Path.build m in
    let target = Path.Build.set_extension m ~ext:".ml" in
    let args = [ Command.Args.Dep source; Hidden_targets [ target ] ] in
    let build_dir = (Super_context.context sctx).build_dir in
    Command.run ~dir:(Path.build build_dir) coqpp args
  in
  List.rev_map ~f:mlg_rule mlg_files |> Super_context.add_rules ~loc ~dir sctx

let setup_extraction_cctx_and_modules ~sctx ~dir ~dir_contents
    (s : Extraction.t) =
  let+ cctx =
    let* theories_deps =
      theories_deps_requires_for_user_written ~dir s.buildable
    in
    let theories_deps = Resolve.Memo.lift theories_deps in
    let theory_dirs = Path.Build.Set.empty in
    Context.create sctx ~dir ~theories_deps ~theory_dirs (`Extraction s)
  and+ coq = Dir_contents.coq dir_contents in
  (cctx, Coq_sources.extract coq s)

let setup_extraction_rules ~sctx ~dir ~dir_contents (s : Extraction.t) =
  let wrapper_name = "DuneExtraction" in
  let* cctx, coq_module =
    setup_extraction_cctx_and_modules ~sctx ~dir ~dir_contents s
  in
  let ml_targets =
    Extraction.ml_target_fnames s |> List.map ~f:(Path.Build.relative dir)
  in
  let theories_deps =
    theories_deps_requires_for_user_written ~dir s.buildable
  in
  let source_rule =
    let theories = source_rule ~sctx theories_deps in
    let open Action_builder.O in
    theories >>> Action_builder.path (Path.build (Coq_module.source coq_module))
  in
  let* mode = select_native_mode ~sctx ~dir s.buildable in
  setup_coqc_rule cctx ~dir ~sctx ~loc:s.buildable.loc ~file_targets:ml_targets
    ~source_rule ~stanza_flags:s.buildable.flags ~theories_deps
    ~use_stdlib:s.buildable.use_stdlib coq_module ~mode ~wrapper_name
    ~stanza:(`Extraction s)

let coqtop_args_extraction ~sctx ~dir ~dir_contents (s : Extraction.t)
    coq_module =
  let theories_deps =
    theories_deps_requires_for_user_written ~dir s.buildable
  in
  let use_stdlib = s.buildable.use_stdlib in
  let wrapper_name = "DuneExtraction" in
  let open Action_builder.O in
  let* cctx, _ =
    Action_builder.of_memo
    @@ setup_extraction_cctx_and_modules ~sctx ~dir ~dir_contents s
  in
  let* expander = Action_builder.of_memo @@ Super_context.expander sctx ~dir in
  let* mode =
    Action_builder.of_memo @@ select_native_mode ~sctx ~dir s.buildable
  in
  let+ coq_flags =
    coq_flags ~expander ~dir ~stanza_flags:s.buildable.flags ~sctx
  in
  Command.Args.As coq_flags
  :: Command.Args.S [ Context.coqc_native_flags ~mode cctx ]
  :: Context.coqc_file_flags ~dir ~theories_deps ~wrapper_name ~use_stdlib cctx
       coq_module

let deps_of ~dir ~boot_type mod_ =
  (* TODO fix *)
  let kind = failwith "TODO dune coq top unsupported" in
  let sctx = failwith "" in
  ignore kind;
  ignore sctx;
  ignore dir;
  ignore boot_type;
  ignore mod_;
  assert false
(* Action_builder.of_memo_join
   @@ Deps.of_ ~sctx ~theories:[] ~kind ~dir ~boot_type mod_ *)
