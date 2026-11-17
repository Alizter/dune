open Import
open Memo.O

include struct
  open Dune_pkg
  module Package_variable = Package_variable
  module Substs = Substs
  module Checksum = Checksum
  module Source = Source
  module Build_command = Lock_dir.Build_command
  module Pkg_info = Lock_dir.Pkg_info
  module Depexts = Lock_dir.Depexts
  module Digest_feed = Dune_digest.Feed
  module Dune_dep = Dune_dep
end

module Variable = struct
  type value = OpamVariable.variable_contents =
    | B of bool
    | S of string
    | L of string list

  type t = Package_variable_name.t * value

  let value_repr =
    Repr.variant
      "package-variable-value"
      [ Repr.case "Bool" Repr.bool ~proj:(function
          | B b -> Some b
          | _ -> None)
      ; Repr.case "String" Repr.string ~proj:(function
          | S s -> Some s
          | _ -> None)
      ; Repr.case "Strings" (Repr.list Repr.string) ~proj:(function
          | L xs -> Some xs
          | _ -> None)
      ]
  ;;

  let repr = Repr.pair Package_variable_name.repr value_repr

  let dune_value : value -> Value.t list = function
    | B b -> [ String (Bool.to_string b) ]
    | S s -> [ String s ]
    | L s -> List.map s ~f:(fun x -> Value.String x)
  ;;

  let of_values : dir:Path.t -> Value.t list -> value =
    fun ~dir xs ->
    match List.map xs ~f:(Value.to_string ~dir) with
    | [ x ] -> S x
    | xs -> L xs
  ;;
end

module Package_universe = struct
  (* A type of group of packages that are co-installed. Multiple different
     versions of a package may be co-installed into the same universe.

     Note that a dev tool universe just contains the package for the dev tool
     itself and not its dependencies, which are installed into the
     [Dependencies _] universe for the default context so they may be
     shared with the project's dependencies. *)
  type t =
    | Dependencies of Context_name.t
    | Dev_tool of Dune_pkg.Dev_tool.t

  let equal a b =
    match a, b with
    | Dependencies a, Dependencies b -> Context_name.equal a b
    | Dev_tool a, Dev_tool b -> Dune_pkg.Dev_tool.equal a b
    | _ -> false
  ;;

  let hash t =
    match t with
    | Dependencies context_name ->
      Tuple.T2.hash Int.hash Context_name.hash (0, context_name)
    | Dev_tool dev_tool -> Tuple.T2.hash Int.hash Dune_pkg.Dev_tool.hash (1, dev_tool)
  ;;

  let context_name = function
    | Dependencies context_name -> context_name
    | Dev_tool _ ->
      (* Dev tools can only be built in the default context. *)
      Context_name.default
  ;;

  let lock_dir_path t =
    match t with
    | Dependencies ctx -> Lock_dir.get_path ctx
    | Dev_tool dev_tool ->
      Lock_dir.dev_tool_lock_dir dev_tool |> Option.some |> Memo.return
  ;;

  let lock_dir t =
    match t with
    | Dependencies ctx -> Lock_dir.get_exn ctx
    | Dev_tool dev_tool -> Lock_dir.of_dev_tool dev_tool
  ;;
end

module Pkg_digest = struct
  module T = struct
    type t =
      { name : Package.Name.t
      ; version : Package_version.t
      ; lockfile_and_dependency_digest : Dune_digest.t
        (* A hash of the package's lockfile as well as of the digests of all
           the package's dependencies. *)
      }

    let equal { name; version; lockfile_and_dependency_digest } t =
      Package.Name.equal name t.name
      && Package_version.equal version t.version
      && Dune_digest.equal lockfile_and_dependency_digest t.lockfile_and_dependency_digest
    ;;

    let compare { name; version; lockfile_and_dependency_digest } t =
      let open Ordering.O in
      let= () = Package.Name.compare name t.name in
      let= () = Package_version.compare version t.version in
      Dune_digest.compare lockfile_and_dependency_digest t.lockfile_and_dependency_digest
    ;;

    let to_dyn { name; version; lockfile_and_dependency_digest } =
      Dyn.record
        [ "name", Package.Name.to_dyn name
        ; "version", Package_version.to_dyn version
        ; ( "lockfile_and_dependency_digest"
          , Dune_digest.to_dyn lockfile_and_dependency_digest )
        ]
    ;;

    let hash { name; version; lockfile_and_dependency_digest } =
      Tuple.T3.hash
        Package.Name.hash
        Package_version.hash
        Dune_digest.hash
        (name, version, lockfile_and_dependency_digest)
    ;;

    let digest_repr = Repr.view Repr.string ~to_:Dune_digest.to_string

    let repr =
      Repr.record
        "pkg-digest"
        [ Repr.field "name" Package.Name.repr ~get:(fun t -> t.name)
        ; Repr.field "version" Package_version.repr ~get:(fun t -> t.version)
        ; Repr.field "lockfile_and_dependency_digest" digest_repr ~get:(fun t ->
            t.lockfile_and_dependency_digest)
        ]
    ;;
  end

  include T
  include Comparable.Make (T)

  let to_string { name; version; lockfile_and_dependency_digest } =
    sprintf
      "%s.%s-%s"
      (Package.Name.to_string name)
      (Package_version.to_string version)
      (Dune_digest.to_string lockfile_and_dependency_digest)
  ;;

  let create lockfile_pkg depends_pkg_digests =
    let lockfile_and_dependency_digest =
      Digest_feed.compute_digest
        (Digest_feed.tuple2 Lock_dir.Pkg.digest_feed (Digest_feed.repr (Repr.list repr)))
        (Dune_pkg.Lock_dir.Pkg.remove_locs lockfile_pkg, depends_pkg_digests)
    in
    let name = lockfile_pkg.info.name in
    let version = lockfile_pkg.info.version in
    { name; version; lockfile_and_dependency_digest }
  ;;
end

module Paths = struct
  (* The [paths] of a package are the information about the artifacts
     that we know {e without} executing any commands. *)
  type 'a t =
    { source_dir : 'a
    ; target_dir : 'a
    ; extra_sources : 'a
    ; name : Package.Name.t
    ; install_roots : 'a Install.Roots.t Lazy.t
    ; install_paths : 'a Install.Paths.t Lazy.t
    ; prefix : 'a
    }

  let map_path t ~f =
    { t with
      source_dir = f t.source_dir
    ; target_dir = f t.target_dir
    ; extra_sources = f t.extra_sources
    ; install_roots = Lazy.map ~f:(Install.Roots.map ~f) t.install_roots
    ; install_paths = Lazy.map ~f:(Install.Paths.map ~f) t.install_paths
    ; prefix = f t.prefix
    }
  ;;

  let install_roots ~target_dir ~relative =
    Install.Roots.opam_from_prefix ~relative target_dir
  ;;

  let install_paths roots package ~relative = Install.Paths.make ~relative ~package ~roots

  let of_root name ~root ~source_dir ~install_dir ~relative =
    let source_dir = relative root source_dir in
    let target_dir = relative root install_dir in
    let extra_sources = relative root "extra_source" in
    let install_roots = lazy (install_roots ~target_dir ~relative) in
    let install_paths = lazy (install_paths (Lazy.force install_roots) name ~relative) in
    { source_dir
    ; target_dir
    ; extra_sources
    ; name
    ; install_paths
    ; install_roots
    ; prefix = target_dir
    }
  ;;

  let with_prefix t prefix =
    let roots = lazy (install_roots ~target_dir:prefix ~relative:Path.relative) in
    { t with
      target_dir = prefix
    ; prefix
    ; install_roots = roots
    ; install_paths =
        lazy (install_paths (Lazy.force roots) t.name ~relative:Path.relative)
    }
  ;;

  let extra_source t extra_source = Path.append_local t.extra_sources extra_source

  let extra_source_build t extra_source =
    Path.Build.append_local t.extra_sources extra_source
  ;;

  let make pkg_digest universe =
    let root =
      match (universe : Package_universe.t) with
      | Dependencies ctx ->
        Path.Build.L.relative
          Private_context.t.build_dir
          [ Context_name.to_string ctx; ".pkg"; Pkg_digest.to_string pkg_digest ]
      | Dev_tool dev_tool -> Pkg_dev_tool.universe_install_path dev_tool
    in
    of_root
      pkg_digest.name
      ~root
      ~source_dir:"source"
      ~install_dir:"target"
      ~relative:Path.Build.relative
  ;;

  let make_install_cookie target_dir ~relative = relative target_dir "cookie"

  let install_cookie' target_dir =
    make_install_cookie target_dir ~relative:Path.Build.relative
  ;;

  let install_cookie t = make_install_cookie t.target_dir ~relative:Path.relative

  let install_file t =
    Path.Build.relative
      t.source_dir
      (sprintf "%s.install" (Package.Name.to_string t.name))
  ;;

  let config_file t =
    Path.Build.relative t.source_dir (sprintf "%s.config" (Package.Name.to_string t.name))
  ;;

  let install_paths t = Lazy.force t.install_paths
  let install_roots t = Lazy.force t.install_roots
end

let candidate_paths candidate =
  Paths.of_root
    (Pkg_sources.Candidate.name candidate)
    ~root:(Pkg_sources.Candidate.artifact_root candidate)
    ~source_dir:"."
    ~install_dir:"_install"
    ~relative:Path.Build.relative
;;

module Install_cookie = struct
  (* The install cookie represents a serialized representation of all the
     installed artifacts and variables.

     The install cookie of a package is the source of all data we must refer to
     address a package's artifacts.

     It is constructed after we've built and installed the packages. In this
     sense, it is the "installation trace" that we must refer to so that we
     don't have to know anything about the installation procedure.
  *)

  module Gen = struct
    type 'files t =
      { files : 'files
      ; variables : Variable.t list
      }

    let repr files_repr =
      Repr.record
        "install-cookie"
        [ Repr.field "files" files_repr ~get:(fun t -> t.files)
        ; Repr.field "variables" (Repr.list Variable.repr) ~get:(fun t -> t.variables)
        ]
    ;;
  end

  type t = Path.t list Section.Map.t Gen.t

  module Persistent = Persistent.Make (struct
      type nonrec t = (Section.t * Path.t list) list Gen.t

      let sharing = false
      let name = "INSTALL-COOKIE"
      let version = 4
      let repr = Gen.repr (Repr.list (Repr.pair Section.repr (Repr.list Path.repr)))
    end)

  let load_exn f =
    match Persistent.load f with
    | Some f -> { f with files = Section.Map.of_list_exn f.files }
    | None -> User_error.raise ~loc:(Loc.in_file f) [ Pp.text "unable to load" ]
  ;;

  let dump path (t : t) =
    Persistent.dump path { t with files = Section.Map.to_list t.files }
  ;;

  let read (paths : Path.t Paths.t) =
    let open Action_builder.O in
    let path = Paths.install_cookie paths in
    let+ () = path |> Dep.file |> Action_builder.dep in
    load_exn path
  ;;
end

module Dependency = struct
  type t =
    { paths : Path.t Paths.t
    ; files : Path.t list Section.Map.t
    ; variables : Variable.value Package_variable_name.Map.t
    ; exported_env : String_with_vars.t Dune_lang.Action.Env_update.t list
    ; export_paths : Path.t Paths.t
    }

  let load paths ~variables ~exported_env =
    let open Action_builder.O in
    let cookie = Paths.install_cookie paths in
    let* () = Action_builder.path cookie in
    let { Install_cookie.Gen.files; variables = installed_variables } =
      Install_cookie.load_exn cookie
    in
    let+ () = Section.Map.values files |> List.concat |> Action_builder.paths in
    let variables =
      Package_variable_name.Map.superpose
        (Package_variable_name.Map.of_list_exn installed_variables)
        variables
    in
    { paths; files; variables; exported_env; export_paths = paths }
  ;;

  let install_entries { paths; files; _ } =
    Section.Map.to_list files
    |> List.concat_map ~f:(fun (section, files) ->
      let prefix = Install.Paths.get (Paths.install_paths paths) section in
      List.map files ~f:(fun src ->
        let dst = Path.reach src ~from:prefix in
        Install.Entry.Expanded.make section ~dst ~kind:File src))
  ;;

  let binaries { paths; files; _ } =
    let { Install.Roots.bin; _ } = Paths.install_roots paths in
    Section.Map.Multi.find files Bin
    |> List.filter ~f:(fun path -> Path.equal (Path.parent_exn path) bin)
  ;;
end

module Value_list_env = struct
  (* A representation of an environment where each variable can hold a
     list of [Value.t]. Each variable will be encoded into a delimited
     string (in the style of the PATH variable). *)
  type t = Value.t list Env.Map.t

  let global : t Lazy.t =
    let parse_strings s = Bin.parse s |> List.map ~f:(fun s -> Value.String s) in
    let of_env env : t = Env.to_map env |> Env.Map.map ~f:parse_strings in
    lazy (of_env (Global.env ()))
  ;;

  (* Concatenate a list of values in the style of lists found in
     environment variables, such as PATH *)
  let string_of_env_values values =
    List.map values ~f:(function
      | Value.String s -> s
      | Dir s | Path s -> Path.to_absolute_filename s)
    |> Bin.encode_strings
  ;;

  let to_env (t : t) = Env.Map.map t ~f:string_of_env_values |> Env.of_map
  let get_path t = Env.Map.find t Env_path.var

  (* [extend_concat_path a b] adds all variables from [b] to [a]
     overwriting any existing values of those variables in [a] except for PATH
     which is set to the concatenation of the PATH variables from [a] and [b]
     with the PATH entries from [b] preceding the PATH entries from
     [a]. If only one of the arguments contains a PATH variable then
     its value will be the value of PATH in the result, however if
     neither argument contains a PATH variable then PATH will be unset
     in the result. *)
  let extend_concat_path a b =
    let extended = Env.Map.superpose b a in
    let concated_path =
      match get_path a, get_path b with
      | None, None -> None
      | Some x, None | None, Some x -> Some x
      | Some a, Some b -> Some (b @ a)
    in
    match concated_path with
    | None -> extended
    | Some concated_path -> Env.Map.set extended Env_path.var concated_path
  ;;

  (* Adds a path to an env where variables are associated with lists
     of paths. The path is prepended to the list associated with the
     given variable and a new binding is added to the env if the
     variable is not yet part of the env. *)
  let add_path (t : t) var path : t =
    Env.Map.update t var ~f:(fun paths ->
      let paths = Option.value paths ~default:[] in
      Some (Value.Dir path :: paths))
  ;;
end

module Env_update = struct
  include Dune_lang.Action.Env_update

  (* Handle the :=, +=, =:, and =+ opam environment update operators.

     The operators with colon character update a variable, adding a
     leading/trailing separator (e.g. the ':' chars in PATH on unix)
     if the variable was initially unset or empty, while the operators
     with a plus character add no leading/trailing separator in such a
     case.

     Updates where the newly added value is the empty string are
     ignored since opam refuses to add empty strings to list
     variables.*)
  let update kind ~new_v ~old_v ~f =
    if new_v = ""
    then old_v
    else (
      match kind with
      | `Colon ->
        let old_v =
          match old_v with
          | None | Some [] -> [ Value.String "" ]
          | Some v -> v
        in
        Some (f ~old_v ~new_v)
      | `Plus ->
        (match old_v with
         | None | Some [] -> Some [ Value.String new_v ]
         | Some old_v -> Some (f ~old_v ~new_v)))
  ;;

  let append = update ~f:(fun ~old_v ~new_v -> old_v @ [ Value.String new_v ])
  let prepend = update ~f:(fun ~old_v ~new_v -> Value.String new_v :: old_v)

  let set env { op; var = k; value = new_v } =
    Env.Map.update env k ~f:(fun old_v ->
      let append = append ~new_v ~old_v in
      let prepend = prepend ~new_v ~old_v in
      match op with
      | Eq ->
        if new_v = ""
        then if Sys.win32 then None else Some [ String "" ]
        else Some [ Value.String new_v ]
      | PlusEq -> prepend `Plus
      | ColonEq -> prepend `Colon
      | EqPlus -> append `Plus
      | EqColon -> append `Colon
      | EqPlusEq ->
        (* TODO nobody uses this AFAIK *)
        assert false)
  ;;
end

module Source_input = Pkg_sources.Source_input

module Layout = struct
  type t =
    { context : Context_name.t
    ; root : Path.Build.t
    ; dependencies : Dependency.t list
    }

  let dependencies { dependencies; _ } = dependencies

  let materialize context dependencies =
    let open Action_builder.O in
    let packages =
      Package.Name.Set.of_list_map dependencies ~f:(fun (dep : Dependency.t) ->
        dep.paths.name)
    in
    let* () = Install_layout.deps context packages in
    let root = Install_layout.root context packages in
    let prefix = Path.build root in
    let+ dependencies =
      Action_builder.List.map dependencies ~f:(fun (dependency : Dependency.t) ->
        let+ files =
          Action_builder.of_memo
            (Install_layout.files_by_section context ~root dependency.paths.name)
        in
        { dependency with paths = Paths.with_prefix dependency.paths prefix; files })
    in
    { context; root; dependencies }
  ;;
end

module Pkg = struct
  module Id = Id.Make ()

  type t =
    { id : Id.t
    ; context : Context_name.t
    ; kind : [ `Dune | `Opam ] Memo.Lazy.t
    ; build_command : Build_command.t option
    ; install_command : Dune_lang.Action.t option
    ; depends : t list
    ; depends_on_dune : bool
      (* whether the package declares a dependency on Dune, even if Dune is stripped from [depends] *)
    ; depexts : Depexts.t list
    ; lock_exported_env : String_with_vars.t Env_update.t list
    ; info : Pkg_info.t
    ; paths : Path.t Paths.t
    ; write_paths : Path.Build.t Paths.t
    ; files_dir : Path.Build.t
    ; mounted : Pkg_sources.Candidate.t option
    ; exported_env : string Env_update.t list
    }

  module Top_closure = Top_closure.Make (Id.Set) (Monad.Id)

  let top_closure depends =
    match
      Top_closure.top_closure depends ~key:(fun t -> t.id) ~deps:(fun t -> t.depends)
    with
    | Ok s -> s
    | Error cycle ->
      User_error.raise
        [ Pp.text "the following packages form a cycle:"
        ; Pp.chain cycle ~f:(fun pkg ->
            Pp.verbatim (Package.Name.to_string pkg.info.name))
        ]
  ;;

  let deps_closure t = top_closure t.depends

  let native_dependencies context packages =
    match packages with
    | [] -> Action_builder.return []
    | _ ->
      let names = Package.Name.Set.of_list_map packages ~f:(fun t -> t.info.name) in
      let prefix = Install_layout.root context names |> Path.build in
      let dependencies =
        List.map packages ~f:(fun t ->
          let paths =
            let paths = Paths.with_prefix t.paths prefix in
            match t.mounted with
            | None -> paths
            | Some candidate ->
              { paths with
                source_dir = Path.build (Pkg_sources.Candidate.artifact_root candidate)
              }
          in
          { Dependency.paths
          ; files = Section.Map.empty
          ; variables = Pkg_info.variables t.info
          ; exported_env = t.lock_exported_env
          ; export_paths = paths
          })
      in
      let open Action_builder.O in
      let+ layout = Layout.materialize context dependencies in
      Layout.dependencies layout
  ;;

  let kind t = Memo.Lazy.force t.kind

  let classify packages =
    Memo.parallel_map packages ~f:(fun t ->
      let+ kind = kind t in
      t, kind)
  ;;

  let partition classified =
    List.partition_map classified ~f:(function
      | t, `Dune -> Left t
      | t, `Opam -> Right t)
  ;;

  let dependency t =
    let open Action_builder.O in
    let* kind = Action_builder.of_memo (kind t) in
    match kind with
    | `Opam ->
      Dependency.load
        t.paths
        ~variables:(Pkg_info.variables t.info)
        ~exported_env:t.lock_exported_env
    | `Dune ->
      let+ dependencies = native_dependencies t.context [ t ] in
      List.hd dependencies
  ;;

  let dep t =
    let open Action_builder.O in
    let* kind = Action_builder.of_memo (kind t) in
    match kind with
    | `Opam -> Action_builder.path t.paths.target_dir
    | `Dune -> Action_builder.ignore (dependency t)
  ;;

  let deps context packages =
    let open Action_builder.O in
    let* native, opaque = Action_builder.of_memo (classify packages) >>| partition in
    let* (_ : Dependency.t list) = native_dependencies context native in
    Action_builder.List.iter opaque ~f:dep
  ;;

  let dependencies context packages =
    let open Action_builder.O in
    let* native, _ = Action_builder.of_memo (classify packages) >>| partition in
    let* native = native_dependencies context native in
    let native =
      Package.Name.Map.of_list_map_exn native ~f:(fun dependency ->
        dependency.paths.name, dependency)
    in
    Action_builder.List.map packages ~f:(fun t ->
      match Package.Name.Map.find native t.info.name with
      | Some dependency -> Action_builder.return dependency
      | None -> dependency t)
  ;;

  let package_deps t = deps t.context (deps_closure t)

  let install_roots t =
    let default_install_roots = Paths.install_roots t.paths in
    match Pkg_toolchain.is_compiler_package_with_toolchains_enabled t.info.name with
    | false -> default_install_roots
    | true ->
      (* Compiler packages store their libraries in a subdirectory named "ocaml". *)
      { default_install_roots with
        lib_root = Path.relative default_install_roots.lib_root "ocaml"
      }
  ;;

  (* Given a list of packages, construct an env containing variables
     set by each package. Variables containing delimited lists of
     paths (e.g. PATH) which appear in multiple package's envs are
     concatenated in the reverse order of their associated packages in
     the input list. Environment updates via the `exported_env` field
     (equivalent to opam's `setenv` field) are applied for each
     package in the same order as the argument list. *)
  let build_env_of_deps ts =
    List.fold_left ts ~init:Env.Map.empty ~f:(fun env t ->
      let env =
        let roots = install_roots t in
        let init = Value_list_env.add_path env Env_path.var roots.bin in
        let vars = Install.Roots.to_env_without_path roots ~relative:Path.relative in
        List.fold_left vars ~init ~f:(fun acc (var, path) ->
          Value_list_env.add_path acc var path)
      in
      List.fold_left t.exported_env ~init:env ~f:Env_update.set)
  ;;

  let build_env_of_classified classified =
    let native_roots =
      match partition classified |> fst with
      | [] -> None
      | first :: _ as native ->
        let names = Package.Name.Set.of_list_map native ~f:(fun t -> t.info.name) in
        let prefix = Install_layout.root first.context names |> Path.build in
        Some (Install.Roots.opam_from_prefix prefix ~relative:Path.relative)
    in
    List.fold_left
      classified
      ~init:(Env.Map.empty, native_roots)
      ~f:(fun (env, native_roots) (t, kind) ->
        let roots, native_roots =
          match kind with
          | `Dune -> native_roots, None
          | `Opam -> Some (install_roots t), native_roots
        in
        let env =
          match roots with
          | None -> env
          | Some roots ->
            let init = Value_list_env.add_path env Env_path.var roots.bin in
            let vars = Install.Roots.to_env_without_path roots ~relative:Path.relative in
            List.fold_left vars ~init ~f:(fun acc (var, path) ->
              Value_list_env.add_path acc var path)
        in
        List.fold_left t.exported_env ~init:env ~f:Env_update.set, native_roots)
    |> fst
  ;;

  (* [build_env t] returns an env containing paths containing all the
     tools and libraries required to build the package [t] inside the
     faux opam directory contained in the _build dir. *)
  let build_env t = classify (deps_closure t) >>| build_env_of_classified

  let base_env t =
    Env.Map.of_list_exn
      [ Opam_switch.opam_switch_prefix_var_name, [ Value.Path t.paths.target_dir ]
      ; Env.Var.of_string "CDPATH", [ Value.String "" ]
      ; Env.Var.of_string "MAKELEVEL", [ Value.String "" ]
      ; ( Env.Var.of_string "OPAM_PACKAGE_NAME"
        , [ Value.String (Package.Name.to_string t.info.name) ] )
      ; ( Env.Var.of_string "OPAM_PACKAGE_VERSION"
        , [ Value.String (Package_version.to_string t.info.version) ] )
      ; Env.Var.of_string "OPAMCLI", [ Value.String "2.0" ]
      ; Env.Var.of_string "OPAMSWITCH", [ Value.String "dune" ]
      ]
  ;;

  (* [exported_value_env t] returns the complete env that will be used
     to build the package [t] *)
  let exported_value_env t =
    let+ package_env = build_env t >>| Env.Map.superpose (base_env t) in
    (* TODO: Run actions in a constrained environment. [Global.env ()] is the
       environment from which dune was executed, and some of the environment
       variables may affect builds in unintended ways and make builds less
       reproducible. However other environment variables must be set in order
       for build actions to run successfully, such as $PATH on systems where the
       shell's default $PATH variable doesn't include the location of standard
       programs or build tools (e.g. NixOS). *)
    Value_list_env.extend_concat_path (Lazy.force Value_list_env.global) package_env
  ;;

  let exported_env t = exported_value_env t >>| Value_list_env.to_env
end

module Action_expander = struct
  module Expander = struct
    include Expander0

    type t =
      { paths : Path.t Paths.t
      ; artifacts : Path.t Filename.Map.t Memo.t
      ; depends :
          (Variable.value Package_variable_name.Map.t * Path.t Paths.t) Package.Name.Map.t
            Memo.t
      ; depexts : Depexts.t list
      ; context : Context_name.t
      ; version : Package_version.t
      ; env : Value.t list Env.Map.t
      ; path : Path.t list
      }

    let map_exe _ x =
      (* TODO *)
      x
    ;;

    let dune_section_of_pform : Pform.Var.Pkg.Section.t -> Section.t = function
      | Lib -> Lib
      | Libexec -> Libexec
      | Bin -> Bin
      | Sbin -> Sbin
      | Toplevel -> Toplevel
      | Share -> Share
      | Etc -> Etc
      | Doc -> Doc
      | Stublibs -> Stublibs
      | Man -> Man
    ;;

    let section_dir_of_root
          (roots : _ Install.Roots.t)
          (section : Pform.Var.Pkg.Section.t)
      =
      match section with
      | Lib -> roots.lib_root
      | Libexec -> roots.libexec_root
      | Bin -> roots.bin
      | Sbin -> roots.sbin
      | Share -> roots.share_root
      | Etc -> roots.etc_root
      | Doc -> roots.doc_root
      | Man -> roots.man
      | Toplevel -> Path.relative roots.lib_root "toplevel"
      | Stublibs -> Path.relative roots.lib_root "stublibs"
    ;;

    let expand_pkg (paths : Path.t Paths.t) (pform : Pform.Var.Pkg.t) =
      match pform with
      | Build -> Memo.return [ Value.Dir paths.source_dir ]
      | Prefix -> Memo.return [ Value.Dir paths.prefix ]
      | Section_dir section ->
        let roots = Paths.install_roots paths in
        let dir = section_dir_of_root roots section in
        Memo.return [ Value.Dir dir ]
      | Switch | Os _ | Sys_ocaml_version | User | Jobs | Arch | Group ->
        let+ solver_env = Lock_dir.Sys_vars.solver_env in
        Lock_dir.global_variable ~solver_env pform
        |> Option.value_exn
        |> Variable.dune_value
    ;;

    let expand_pkg_macro ~loc (paths : _ Paths.t) deps macro_invocation =
      let* deps = deps in
      let { Package_variable.name = variable_name; scope } =
        match Package_variable.of_macro_invocation ~loc macro_invocation with
        | Ok package_variable -> package_variable
        | Error `Unexpected_macro ->
          Code_error.raise
            "Attempted to treat an unexpected macro invocation as a package variable \
             encoding"
            []
      in
      let variables, paths =
        let package_name =
          match scope with
          | Self -> paths.name
          | Package package_name -> package_name
        in
        match Package.Name.Map.find deps package_name with
        | None -> Package_variable_name.Map.empty, None
        | Some (var, paths) -> var, Some paths
      in
      match
        Option.first_some
          (Package_variable_name.Map.find variables variable_name)
          (Lock_dir.default_package_variable
             ~present:(Option.is_some paths)
             variable_name)
      with
      | Some value -> Memo.return (Ok (Variable.dune_value value))
      | None ->
        (match paths with
         | None -> Memo.return (Error (`Undefined_pkg_var variable_name))
         | Some paths ->
           (match
              Pform.Var.Pkg.Section.of_string
                (Package_variable_name.to_string variable_name)
            with
            | None -> Memo.return (Error (`Undefined_pkg_var variable_name))
            | Some section ->
              let section = dune_section_of_pform section in
              let install_paths = Paths.install_paths paths in
              Memo.return (Ok [ Value.Dir (Install.Paths.get install_paths section) ])))
    ;;

    let expand_pform
          { env = _
          ; paths
          ; artifacts = _
          ; context
          ; path
          ; depends
          ; version = _
          ; depexts = _
          }
          ~source
          (pform : Pform.t)
      : (Value.t list, [ `Undefined_pkg_var of Package_variable_name.t ]) result Memo.t
      =
      let loc = Dune_sexp.Template.Pform.loc source in
      match pform with
      | Var (Pkg var) -> expand_pkg paths var >>| Result.ok
      | Var Context_name ->
        Memo.return (Ok [ Value.String (Context_name.to_string context) ])
      | Var Make ->
        let+ make = Make_prog.which loc context ~path in
        Ok [ Value.Path make ]
      | Macro ({ macro = Pkg | Pkg_self; _ } as macro_invocation) ->
        expand_pkg_macro ~loc paths depends macro_invocation
      | _ -> Expander0.isn't_allowed_in_this_position ~source
    ;;

    let expand_pform_gen t =
      String_expander.Memo.expand ~dir:t.paths.source_dir ~f:(fun ~source pform ->
        expand_pform t ~source pform
        >>| function
        | Ok x -> x
        | Error (`Undefined_pkg_var variable_name) ->
          User_error.raise
            ~loc:(Dune_sexp.Template.Pform.loc source)
            [ Pp.textf
                "Undefined package variable: %s"
                (Package_variable_name.to_string variable_name)
            ])
    ;;

    let slang_expander t sw =
      String_expander.Memo.expand_result_deferred_concat sw ~mode:Many ~f:(expand_pform t)
    ;;

    let eval_blang t blang =
      Slang_expand.eval_blang blang ~dir:t.paths.source_dir ~f:(slang_expander t)
    ;;

    let eval_slangs_located t slangs =
      let slangs =
        List.map slangs ~f:(fun slang ->
          Slang.map_loc slang ~f:Dune_pkg.Lock_dir.loc_in_source_tree)
      in
      Slang_expand.eval_multi_located slangs ~dir:t.paths.source_dir ~f:(slang_expander t)
    ;;

    let filtered_depexts t =
      Memo.List.filter_map t.depexts ~f:(fun (depexts : Depexts.t) ->
        let+ enabled =
          match depexts.enabled_if with
          | `Always -> Memo.return true
          | `Conditional condition -> eval_blang t condition
        in
        if enabled then Some depexts.external_package_names else None)
      >>| List.concat
      >>| List.sort_uniq ~compare:String.compare
    ;;

    let expand_exe_value t value ~loc =
      let+ prog =
        match value with
        | Value.Dir p ->
          User_error.raise
            ~loc
            [ Pp.textf
                "%s is a directory and cannot be used as an executable"
                (Path.to_string_maybe_quoted p)
            ]
        | Path p -> Memo.return @@ Ok p
        | String program ->
          (match Filename.analyze_program_name program with
           | Relative_to_current_dir | Absolute ->
             let dir = t.paths.source_dir in
             Memo.return @@ Ok (Path.relative dir program)
           | In_path ->
             (match program with
              | "dune" ->
                let dune = Path.of_string Sys.executable_name in
                Memo.return @@ Ok dune
              | program ->
                let program = Filename.of_string_exn program in
                let* artifacts = t.artifacts in
                (match Filename.Map.find artifacts program with
                 | Some s -> Memo.return @@ Ok s
                 | None ->
                   Which.which ~path:t.path program
                   >>= (function
                    | Some p -> Memo.return (Ok p)
                    | None ->
                      let+ depexts = filtered_depexts t in
                      let hint =
                        Run_with_path.depexts_hint depexts
                        |> Option.map ~f:(fun pp -> Format.asprintf "%a" Pp.to_fmt pp)
                      in
                      Error
                        (Action.Prog.Not_found.create
                           ?hint
                           ~program
                           ~context:t.context
                           ~loc:(Some loc)
                           ())))))
      in
      Result.map prog ~f:(map_exe t)
    ;;
  end

  module Substitute = struct
    include Substs.Make (Memo)

    module Spec = struct
      type ('src, 'dst) t =
        { (* XXX it's not good to serialize the substitution map like this. We're
             essentially implementing the same substitution procedure but in two
             different places: action geeneration, and action execution.

             The two implementations are bound to drift. Better would be to
             reconstruct everything that is needed to call our one and only
             substitution function. *)
          expander : Expander.t
        ; depends :
            (Variable.value Package_variable_name.Map.t * Path.t Paths.t)
              Package.Name.Map.t
        ; artifacts : Path.t Filename.Map.t
        ; src : 'src
        ; dst : 'dst
        }

      let name = "substitute"
      let version = 5
      let runs_process = false
      let can_run_in_action_runner = false
      let bimap t f g = { t with src = f t.src; dst = g t.dst }
      let is_useful_to_memoize = true

      let variable_value_repr =
        Repr.variant
          "pkg-variable-value"
          [ Repr.case "B" Bool.repr ~proj:(function
              | Variable.B x -> Some x
              | _ -> None)
          ; Repr.case "S" String.repr ~proj:(function
              | Variable.S x -> Some x
              | _ -> None)
          ; Repr.case
              "L"
              Repr.(list String.repr)
              ~proj:(function
                | Variable.L x -> Some x
                | _ -> None)
          ]
      ;;

      let variable_map_repr =
        Repr.view
          Repr.(list (pair Package_variable_name.repr variable_value_repr))
          ~to_:Package_variable_name.Map.to_list
      ;;

      let paths_repr = Repr.T3.repr Path.repr Path.repr Package.Name.repr

      let hash_input_repr =
        Repr.T4.repr
          paths_repr
          Repr.(list (pair Filename.repr Path.repr))
          Repr.(list (pair variable_map_repr paths_repr))
          Repr.(pair Package_version.repr (list Path.repr))
      ;;

      let encode { expander; depends; artifacts; src; dst } input output : Sexp.t =
        let e =
          let paths (p : Path.t Paths.t) = p.source_dir, p.target_dir, p.name in
          Digest.repr
            hash_input_repr
            ( paths expander.paths
            , Filename.Map.to_list artifacts
            , Package.Name.Map.to_list_map depends ~f:(fun _ (m, p) -> m, paths p)
            , (expander.version, expander.path) )
          |> Digest.to_string_raw
        in
        List [ Atom e; input src; output dst ]
      ;;

      let action { expander; depends = _; artifacts = _; src; dst } ~ectx:_ ~eenv:_ =
        let open Fiber.O in
        let* () = Fiber.return () in
        let env (var : Substs.Variable.t) =
          let open Memo.O in
          ((* TODO loc *)
           let loc = Loc.none in
           let source =
             (* TODO it's rather ugly that we're going through the pform machinery
                to do this *)
             { Dune_sexp.Template.Pform.loc; name = ""; payload = None }
           in
           match
             match var with
             | Package var -> Some (Package_variable.to_pform var)
             | Global n ->
               Package_variable_name.to_string n
               |> Pform.Var.of_opam_global_variable_name
               |> Option.map ~f:(fun v -> Pform.Var v)
           with
           | None -> Memo.return @@ Variable.S ""
           | Some pform ->
             Expander.expand_pform expander ~source pform
             >>| (function
              | Error (`Undefined_pkg_var _) ->
                (* these are opam's semantics as far as I understand. *)
                Variable.S ""
              | Ok v ->
                let dir = Path.parent_exn src |> Path.drop_optional_sandbox_root in
                Variable.of_values v ~dir))
          >>| Option.some
        in
        subst env expander.paths.name ~src ~dst |> Memo.run
      ;;
    end

    module A = Action_ext.Make (Spec)

    let action (expander : Expander.t) ~src ~dst =
      let+ depends = expander.depends
      and+ artifacts = expander.artifacts in
      A.action { Spec.expander; depends; artifacts; src; dst }
    ;;
  end

  let rec expand (action : Dune_lang.Action.t) ~(expander : Expander.t) =
    let dir = expander.paths.source_dir in
    match action with
    | Run args ->
      Expander.eval_slangs_located expander args
      >>= (function
       | [] ->
         let loc =
           let loc = function
             | Slang.Nil -> None
             | Slang.Undefined -> None
             | Literal sw -> Some (String_with_vars.loc sw)
             | Form (loc, _) -> Some loc
           in
           let start = List.find_map args ~f:loc in
           let stop =
             List.fold_left args ~init:None ~f:(fun last a ->
               match loc a with
               | None -> last
               | Some _ as s -> s)
           in
           Option.both start stop
           |> Option.map ~f:(fun (start, stop) -> Loc.span start stop)
         in
         User_error.raise
           ?loc
           [ Pp.text "\"run\" action must have at least one argument" ]
       | (prog_loc, prog) :: args ->
         let+ exe =
           let prog = Value.Deferred_concat.force prog ~dir in
           Expander.expand_exe_value expander prog ~loc:prog_loc
         and+ depexts = Expander.filtered_depexts expander in
         let args =
           Array.Immutable.of_list_map args ~f:(fun (_loc, arg) ->
             Value.Deferred_concat.parts arg
             |> Array.Immutable.of_list_map ~f:(fun (arg : Value.t) ->
               match arg with
               | String s -> Run_with_path.Spec.String s
               | Path p | Dir p -> Path p))
         in
         let ocamlfind_destdir = (Lazy.force expander.paths.install_roots).lib_root in
         Run_with_path.action
           ~depexts
           ~pkg:(expander.paths.name, prog_loc)
           exe
           args
           ~ocamlfind_destdir)
    | Progn t ->
      let+ args = Memo.parallel_map t ~f:(expand ~expander) in
      Action.Progn args
    | System arg ->
      let+ arg =
        Expander.expand_pform_gen ~mode:Single expander arg >>| Value.to_string ~dir
      in
      Action.System arg
    | Patch p ->
      let+ patch =
        Expander.expand_pform_gen ~mode:Single expander p >>| Value.to_path ~dir
      in
      Dune_patch.action ~patch
    | Substitute (src, dst) ->
      let* src =
        Expander.expand_pform_gen ~mode:Single expander src >>| Value.to_path ~dir
      and* dst =
        Expander.expand_pform_gen ~mode:Single expander dst
        >>| Value.to_path ~dir
        >>| Expander0.as_in_build_dir ~what:"substitute" ~loc:(String_with_vars.loc dst)
      in
      Substitute.action expander ~src ~dst
    | Withenv (updates, action) -> expand_withenv expander updates action
    | When (condition, action) ->
      Expander.eval_blang expander condition
      >>= (function
       | true -> expand action ~expander
       | false -> Memo.return (Action.progn []))
    | Write_file (path_sw, perm, contents_sw) ->
      let+ path =
        Expander.expand_pform_gen ~mode:Single expander path_sw
        >>| Value.to_path ~dir
        >>| Expander0.as_in_build_dir
              ~what:"write-file"
              ~loc:(String_with_vars.loc path_sw)
      and+ contents =
        Expander.expand_pform_gen ~mode:Single expander contents_sw
        >>| Value.to_string ~dir
      in
      Action.Write_file (path, perm, contents)
    | _ ->
      Code_error.raise
        "Pkg_rules.action_expander.expand: unsupported action"
        [ "action", Dune_lang.Action.to_dyn action ]

  and expand_withenv (expander : Expander.t) updates action =
    let* env, updates =
      let dir = expander.paths.source_dir in
      Memo.List.fold_left
        ~init:(expander.env, [])
        updates
        ~f:(fun (env, updates) ({ Env_update.op = _; var; value } as update) ->
          let+ value =
            let+ value =
              let expander = { expander with env } in
              Expander.expand_pform_gen expander value ~mode:Single
            in
            Value.to_string ~dir value
          in
          let env = Env_update.set env { update with value } in
          let update =
            let value =
              match Env.Map.find env var with
              | Some v -> Value_list_env.string_of_env_values v
              | None ->
                (* TODO *)
                ""
            in
            var, value
          in
          env, update :: updates)
    in
    let+ action =
      let expander = { expander with env } in
      expand action ~expander
    in
    List.fold_left updates ~init:action ~f:(fun action (k, v) ->
      Action.Setenv (Env.Var.to_string k, v, action))
  ;;

  let for_recipe (pkg : Pkg.t) ~context ~path ~env ~direct ~dependencies =
    let { Pkg.paths; info; depexts; _ } = pkg in
    let { Pkg_info.version; _ } = info in
    let variables = Pkg_info.variables info in
    let env =
      Env.add
        env
        ~var:(Env.Var.of_string "OPAM_PACKAGE_NAME")
        ~value:(Package.Name.to_string paths.name)
      |> Env.add
           ~var:(Env.Var.of_string "OPAM_PACKAGE_VERSION")
           ~value:(Package_version.to_string version)
      |> Env.add ~var:(Env.Var.of_string "OPAMCLI") ~value:"2.0"
      |> Env.add ~var:(Env.Var.of_string "OPAMSWITCH") ~value:"dune"
      |> Env.add ~var:(Env.Var.of_string "CDPATH") ~value:""
      |> Env.add ~var:(Env.Var.of_string "MAKELEVEL") ~value:""
      |> Env.add
           ~var:Opam_switch.opam_switch_prefix_var_name
           ~value:(Path.to_absolute_filename paths.prefix)
    in
    let direct_dependencies =
      List.filter dependencies ~f:(fun (dep : Dependency.t) ->
        Package.Name.Set.mem direct dep.paths.name)
    in
    let depends =
      List.map direct_dependencies ~f:(fun (dep : Dependency.t) ->
        dep.paths.name, (dep.variables, dep.paths))
      |> Package.Name.Map.of_list_exn
      |> fun deps -> Package.Name.Map.add_exn deps paths.name (variables, paths)
    in
    let artifacts =
      List.concat_map dependencies ~f:Dependency.binaries
      |> List.fold_left ~init:Filename.Map.empty ~f:(fun acc path ->
        Filename.Map.set
          acc
          (Filename.of_string_exn
             (Bin.strip_exe (Filename.to_string (Path.basename path))))
          path)
    in
    { Expander.name = paths.name
    ; paths
    ; depends = Memo.return depends
    ; artifacts = Memo.return artifacts
    ; depexts
    ; context
    ; path
    ; version
    ; env = Env.to_map env |> Env.Map.map ~f:(fun value -> [ Value.String value ])
    }
  ;;

  module Artifacts_and_deps = struct
    type artifacts_and_deps =
      { binaries : Path.t Filename.Map.t
      ; dep_info :
          (OpamVariable.variable_contents Package_variable_name.Map.t * Path.t Paths.t)
            Package.Name.Map.t
      }

    let empty = { binaries = Filename.Map.empty; dep_info = Package.Name.Map.empty }

    let of_closure closure =
      (match closure with
       | [] -> Memo.return []
       | (first : Pkg.t) :: _ ->
         Action_builder.evaluate_and_collect_facts
           (Pkg.dependencies first.context closure)
         >>| fst)
      |> Memo.map ~f:(fun dependencies ->
        List.fold_left
          dependencies
          ~init:empty
          ~f:(fun { binaries; dep_info } (dependency : Dependency.t) ->
            let binaries =
              Section.Map.Multi.find dependency.files Bin
              |> List.fold_left ~init:binaries ~f:(fun acc bin ->
                Filename.Map.set
                  acc
                  (Filename.of_string_exn
                     (Bin.strip_exe (Path.basename bin |> Filename.to_string)))
                  bin)
            in
            let dep_info =
              Package.Name.Map.add_exn
                dep_info
                dependency.paths.name
                (dependency.variables, dependency.paths)
            in
            { binaries; dep_info }))
    ;;
  end

  (* Expanding a package's variables does not read [env]; only [withenv]
     and the recipe's own environment do. *)
  let expander_with_env context (pkg : Pkg.t) ~env =
    let closure =
      Memo.lazy_
        ~name:"package-dependency-closure"
        ~human_readable_description:(fun () ->
          Pp.textf
            "Computing closure for package %S"
            (Package.Name.to_string pkg.info.name))
        (fun () -> Pkg.deps_closure pkg |> Artifacts_and_deps.of_closure)
    in
    let depends =
      Memo.Lazy.map
        ~name:"package-dependency-info"
        closure
        ~f:(fun { Artifacts_and_deps.dep_info; _ } ->
          Package.Name.Map.add_exn
            dep_info
            pkg.info.name
            (Pkg_info.variables pkg.info, pkg.paths))
      |> Memo.Lazy.force
    in
    let artifacts =
      let+ { Artifacts_and_deps.binaries; _ } = Memo.Lazy.force closure in
      binaries
    in
    { Expander.paths = pkg.paths
    ; artifacts
    ; context
    ; path = Env_path.path (Global.env ())
    ; depends
    ; depexts = pkg.depexts
    ; version = pkg.info.version
    ; env
    }
  ;;

  let expander context pkg =
    let+ env = Pkg.exported_value_env pkg in
    expander_with_env context pkg ~env
  ;;

  let expand_action = expand
  let sandbox = Sandbox_mode.Set.singleton Sandbox_mode.copy

  let expand context (pkg : Pkg.t) action =
    let+ action =
      let* expander = expander context pkg in
      expand action ~expander >>| Action.chdir pkg.paths.source_dir
    in
    (* TODO copying is needed for build systems that aren't dune and those
       with an explicit install step *)
    Action.Full.make ~sandbox action
    |> Action_builder.return
    |> Action_builder.with_no_targets
  ;;

  let build_command context (pkg : Pkg.t) =
    Option.map pkg.build_command ~f:(function
      | Action action -> expand context pkg action
      | Dune ->
        (* CR-someday rgrinberg: respect [dune subst] settings. *)
        Command.run_dyn_prog
          (Action_builder.return (Ok (Path.of_string Sys.executable_name)))
          ~dir:pkg.paths.source_dir
          [ A "build"; A "-p"; A (Package.Name.to_string pkg.info.name) ]
        |> Memo.return)
  ;;

  let install_command context (pkg : Pkg.t) =
    Option.map pkg.install_command ~f:(fun action -> expand context pkg action)
  ;;

  let exported_env (expander : Expander.t) (env : _ Env_update.t) =
    let+ value =
      let+ value = Expander.expand_pform_gen expander env.value ~mode:Single in
      value |> Value.to_string ~dir:expander.paths.source_dir
    in
    { env with value }
  ;;
end

let layout_env { Layout.context; root; dependencies } ~path ~base =
  let open Action_builder.O in
  let roots = Install.Roots.opam_from_prefix root ~relative:Path.Build.relative in
  let env =
    Install.Roots.add_to_env roots Env.empty
    |> Install.Roots.extend_env_concat_path_vars base
  in
  let depends =
    List.map dependencies ~f:(fun (dep : Dependency.t) ->
      dep.paths.name, (dep.variables, dep.paths))
    |> Package.Name.Map.of_list_exn
  in
  Action_builder.List.fold_left dependencies ~init:env ~f:(fun env (dep : Dependency.t) ->
    let expander =
      let paths =
        Paths.map_path dep.export_paths ~f:(fun path ->
          Path.of_string (Path.to_absolute_filename path))
      in
      let depends = Package.Name.Map.set depends paths.name (dep.variables, paths) in
      { Action_expander.Expander.name = paths.name
      ; paths
      ; artifacts = Memo.return Filename.Map.empty
      ; depends = Memo.return depends
      ; depexts = []
      ; context
      ; path
      ; version = Dune_pkg.Package_version.dev
      ; env = Env.to_map env |> Env.Map.map ~f:(fun value -> [ Value.String value ])
      }
    in
    let* updates =
      Action_builder.of_memo
        (Memo.List.map dep.exported_env ~f:(Action_expander.exported_env expander))
    in
    let+ () =
      Action_builder.List.iter updates ~f:(fun { Env_update.var; _ } ->
        Action_builder.dep (Dep.env var))
    in
    List.fold_left updates ~init:expander.env ~f:Env_update.set |> Value_list_env.to_env)
;;

module DB = struct
  let default_system_provided = Package.Name.Set.singleton Dune_pkg.Dune_dep.name

  module Pkg_table = struct
    module Pkg = Lock_dir.Pkg

    type dep =
      { dep_pkg : Pkg.t
      ; dep_loc : Loc.t
      ; dep_pkg_digest : Pkg_digest.t
      }

    type entry =
      { pkg : Pkg.t
      ; deps : dep list
      ; has_dune_dep : bool
      ; pkg_digest : Pkg_digest.t
      }

    let entries_by_name_of_lock_dir
          (lock_dir : Dune_pkg.Lock_dir.t)
          ~platform
          ~system_provided
          ~local_packages
      =
      let pkgs_by_name = Dune_pkg.Lock_dir.packages_on_platform lock_dir ~platform in
      Log.info
        "Package digest index"
        [ "packages", Dyn.int (Package.Name.Map.cardinal pkgs_by_name) ];
      let cache =
        (* Cache so that the digest of each package is only computed once *)
        Package.Name.Table.create 10
      in
      let rec compute_entry (pkg : Pkg.t) ~seen_set ~seen_list =
        if Package.Name.Set.mem seen_set pkg.info.name
        then
          User_error.raise
            [ Pp.textf "Dependency cycle between packages:"
            ; Pp.chain
                (List.rev (pkg :: seen_list))
                ~f:(fun (pkg : Pkg.t) ->
                  Pp.textf
                    "%s.%s"
                    (Package.Name.to_string pkg.info.name)
                    (Package_version.to_string pkg.info.version))
            ];
        Package.Name.Table.find_or_add cache pkg.info.name ~f:(fun name ->
          let seen_set = Package.Name.Set.add seen_set name in
          let seen_list = pkg :: seen_list in
          let has_dune_dep, deps =
            Dune_pkg.Lock_dir.Conditional_choice.choose_for_platform pkg.depends ~platform
            |> Option.value ~default:[]
            |> List.fold_right
                 ~init:(false, [])
                 ~f:
                   (fun
                     { Dune_pkg.Lock_dir.Dependency.name; loc = dep_loc }
                     (has_dune_dep, acc)
                   ->
                   match
                     ( Dune_lang.Package_name.equal name Dune_dep.name
                     , Package.Name.Set.mem system_provided name )
                   with
                   | true, _ -> true, acc
                   | false, true -> has_dune_dep, acc
                   | _, false when Package.Name.Set.mem local_packages name ->
                     has_dune_dep, acc
                   | _, false ->
                     let dep_pkg = Package.Name.Map.find_exn pkgs_by_name name in
                     let dep_entry = compute_entry dep_pkg ~seen_set ~seen_list in
                     ( has_dune_dep
                     , { dep_pkg; dep_loc; dep_pkg_digest = dep_entry.pkg_digest } :: acc
                     ))
          in
          let pkg_digest =
            Pkg_digest.create
              pkg
              (List.map deps ~f:(fun { dep_pkg_digest; _ } -> dep_pkg_digest))
          in
          { pkg; deps; has_dune_dep; pkg_digest })
      in
      Package.Name.Map.map
        pkgs_by_name
        ~f:(compute_entry ~seen_set:Package.Name.Set.empty ~seen_list:[])
    ;;

    (* Associate each package's digest with the package and its dependencies. *)
    type t = entry Pkg_digest.Map.t

    let of_entries_by_name entries =
      Package.Name.Map.values entries
      |> Pkg_digest.Map.of_list_map_exn ~f:(fun entry -> entry.pkg_digest, entry)
    ;;

    let of_lock_dir lock_dir ~platform ~system_provided ~local_packages =
      entries_by_name_of_lock_dir lock_dir ~platform ~system_provided ~local_packages
      |> of_entries_by_name
    ;;

    let project_entries =
      Memo.create
        "project-package-digest-index"
        ~input:(module Context_name)
        (fun ctx ->
           let+ lock_dir = Lock_dir.get_exn ctx
           and+ platform = Lock_dir.Sys_vars.solver_env
           and+ { Dune_load_workspace.packages; _ } = Dune_load_workspace.load () in
           entries_by_name_of_lock_dir
             lock_dir
             ~platform
             ~system_provided:default_system_provided
             ~local_packages:(Package.Name.Set.of_keys packages))
    ;;

    (* Helper which is called when both tables have an entry with the same
       digest. This happens when two lock directories have a package in common
       and the transitive dependency closure of the package is identical in both
       lock directories. Here we assert that the packages and their immediate
       dependencies are identical as a sanity check. *)
    let union_check
          pkg_digest
          ({ pkg = pkg_a; deps = deps_a; has_dune_dep = _; pkg_digest = _ } as entry)
          { pkg = pkg_b; deps = deps_b; has_dune_dep = _; pkg_digest = _ }
      =
      if not (Pkg.equal (Pkg.remove_locs pkg_a) (Pkg.remove_locs pkg_b))
      then
        Code_error.raise
          "Two packages with the same pkg digest differ in their fields"
          [ "pkg_digest", Pkg_digest.to_dyn pkg_digest
          ; "pkg_a", Pkg.to_dyn pkg_a
          ; "pkg_b", Pkg.to_dyn pkg_b
          ];
      List.combine deps_a deps_b
      |> List.iter ~f:(fun (dep_a, dep_b) ->
        if not (Pkg.equal (Pkg.remove_locs dep_a.dep_pkg) (Pkg.remove_locs dep_b.dep_pkg))
        then
          Code_error.raise
            "Two packages with the same pkg digest differ in their dependencies"
            [ "pkg_digest", Pkg_digest.to_dyn pkg_digest
            ; "pkg_a", Pkg.to_dyn pkg_a
            ; "pkg_b", Pkg.to_dyn pkg_b
            ; "dep_of_a", Pkg.to_dyn dep_a.dep_pkg
            ; "dep_of_b", Pkg.to_dyn dep_b.dep_pkg
            ]);
      Some entry
    ;;

    let empty = Pkg_digest.Map.empty
    let union = Pkg_digest.Map.union ~f:union_check
    let union_all = Pkg_digest.Map.union_all ~f:union_check

    let of_dev_tool_deps_if_lock_dir_exists dev_tool ~platform ~system_provided =
      let+ lock_dir_opt = Lock_dir.of_dev_tool_if_lock_dir_exists dev_tool in
      Option.map
        lock_dir_opt
        ~f:(of_lock_dir ~platform ~system_provided ~local_packages:Package.Name.Set.empty)
    ;;

    let all_existing_dev_tools =
      Memo.lazy_ ~name:"all-existing-dev-tools" (fun () ->
        let* platform = Lock_dir.Sys_vars.solver_env in
        let+ xs =
          Memo.List.map
            Pkg_dev_tool.all
            ~f:
              (of_dev_tool_deps_if_lock_dir_exists
                 ~platform
                 ~system_provided:default_system_provided)
        in
        List.filter_opt xs |> union_all)
    ;;
  end

  module Id = Id.Make ()

  type t =
    { id : Id.t
    ; pkg_digest_table : Pkg_table.t
    }

  let equal x y = Id.equal x.id y.id
  let create ~pkg_digest_table = { id = Id.gen (); pkg_digest_table }

  let pkg_digest_of_name entries_by_name pkg_name =
    let { Pkg_table.pkg_digest; _ } =
      Package.Name.Map.find_exn entries_by_name pkg_name
    in
    pkg_digest
  ;;

  let project_pkg_digest ctx pkg_name =
    let+ entries = Memo.exec Pkg_table.project_entries ctx in
    pkg_digest_of_name entries pkg_name
  ;;

  let of_ctx =
    let of_ctx_memo =
      Memo.create
        "pkg-db"
        ~input:
          (module struct
            type t = Context_name.t * bool

            let to_dyn = Tuple.T2.to_dyn Context_name.to_dyn Dyn.bool
            let hash = Tuple.T2.hash Context_name.hash Bool.hash
            let equal = Tuple.T2.equal Context_name.equal Bool.equal
          end)
        (fun (ctx, allow_sharing) ->
           Per_context.valid ctx
           >>= function
           | false ->
             Code_error.raise "invalid context" [ "context", Context_name.to_dyn ctx ]
           | true ->
             (* Dev tools are built in the default context, so allow their
                dependencies to be shared with the project's if it too is being
                built in the default context. *)
             let allow_sharing = allow_sharing && Context_name.is_default ctx in
             let* entries = Memo.exec Pkg_table.project_entries ctx in
             let+ dev_tools =
               if allow_sharing
               then Memo.Lazy.force Pkg_table.all_existing_dev_tools
               else Memo.return Pkg_table.empty
             in
             let pkg_digest_table =
               Pkg_table.union (Pkg_table.of_entries_by_name entries) dev_tools
             in
             create ~pkg_digest_table)
    in
    fun ctx ~allow_sharing -> Memo.exec of_ctx_memo (ctx, allow_sharing)
  ;;

  (* Returns the db for the given context and the digest of the given package
     within that context. *)
  let of_project_pkg ctx pkg_name =
    let* t = of_ctx ctx ~allow_sharing:true in
    let+ pkg_digest = project_pkg_digest ctx pkg_name in
    t, pkg_digest
  ;;

  (* Returns the db for all dev tools combined with the default context, and
     the digest for the dev tool's package. *)
  let of_dev_tool =
    let system_provided = default_system_provided in
    let inactive_lockdir =
      Memo.lazy_ ~name:"inactive-lockdir-package-db" (fun () ->
        let+ pkg_digest_table = Memo.Lazy.force Pkg_table.all_existing_dev_tools in
        create ~pkg_digest_table)
    in
    let of_dev_tool_memo =
      Memo.create "pkg-db-dev-tool" ~input:(module Dune_pkg.Dev_tool)
      @@ fun dev_tool ->
      let+ lock_dir = Lock_dir.of_dev_tool dev_tool
      and+ platform = Lock_dir.Sys_vars.solver_env in
      let entries =
        Pkg_table.entries_by_name_of_lock_dir
          lock_dir
          ~platform
          ~system_provided
          ~local_packages:Package.Name.Set.empty
      in
      pkg_digest_of_name entries (Pkg_dev_tool.package_name dev_tool)
    in
    fun dev_tool ->
      let+ db =
        Lock_dir.lock_dir_active Context_name.default
        >>= function
        | false -> Memo.Lazy.force inactive_lockdir
        | true -> of_ctx Context_name.default ~allow_sharing:true
      and+ pkg_digest = Memo.exec of_dev_tool_memo dev_tool in
      db, pkg_digest
  ;;
end

module rec Resolve : sig
  val resolve : DB.t -> Loc.t -> Pkg_digest.t -> Package_universe.t -> Pkg.t Memo.t
end = struct
  open Resolve

  module Input = struct
    type t =
      { db : DB.t
      ; pkg_digest : Pkg_digest.t
      ; universe : Package_universe.t
      }

    let equal { db; pkg_digest; universe } t =
      Pkg_digest.equal pkg_digest t.pkg_digest
      && Package_universe.equal universe t.universe
      && DB.equal db t.db
    ;;

    let hash { db = _; pkg_digest; universe } =
      Tuple.T2.hash Pkg_digest.hash Package_universe.hash (pkg_digest, universe)
    ;;

    let to_dyn = Dyn.opaque
  end

  let relocate action =
    let string_with_vars =
      String_with_vars.map_loc ~f:Dune_pkg.Lock_dir.loc_in_source_tree
    in
    let slang = Slang.map_loc ~f:Dune_pkg.Lock_dir.loc_in_source_tree in
    let blang = Slang.Blang.map_loc ~f:Dune_pkg.Lock_dir.loc_in_source_tree in
    Dune_lang.Action.map action ~string_with_vars ~slang ~blang
  ;;

  let relocate_build b =
    match (b : Build_command.t) with
    | Dune -> Build_command.Dune
    | Action a -> Build_command.Action (relocate a)
  ;;

  let is_relocatable_compiler_marker name =
    let relocatable_compiler = Package.Name.of_string "relocatable-compiler" in
    let relocatable = Package.Name.of_string "relocatable" in
    Package.Name.equal name relocatable_compiler || Package.Name.equal name relocatable
  ;;

  let has_relocatable_compiler_marker (info : Pkg_info.t) depends =
    is_relocatable_compiler_marker info.name
    || Pkg.top_closure depends
       |> List.exists ~f:(fun (pkg : Pkg.t) ->
         is_relocatable_compiler_marker pkg.info.name)
  ;;

  let is_compiler_version_relocatable (info : Pkg_info.t) =
    Pkg_toolchain.is_compiler_package_with_toolchains_enabled info.name
    &&
    match Package_version.compare info.version (Package_version.of_string "5.5.0") with
    | Lt -> false
    | Eq | Gt -> true
  ;;

  let resolve_impl { Input.db; pkg_digest; universe = package_universe } =
    match Pkg_digest.Map.find db.pkg_digest_table pkg_digest with
    | None -> Memo.return None
    | Some
        { pkg =
            { Lock_dir.Pkg.build_command
            ; install_command
            ; depends = _
            ; info
            ; exported_env
            ; depexts
            ; enabled_on_platforms = _
            } as pkg
        ; deps
        ; has_dune_dep
        ; pkg_digest = _
        } ->
      assert (Package.Name.equal pkg_digest.name info.name);
      let* platform = Lock_dir.Sys_vars.solver_env in
      let choose_for_current_platform field =
        Dune_pkg.Lock_dir.Conditional_choice.choose_for_platform field ~platform
      in
      let* depends =
        Memo.parallel_map
          deps
          ~f:(fun { DB.Pkg_table.dep_pkg = _; dep_loc; dep_pkg_digest } ->
            let package_universe =
              match package_universe with
              | Dev_tool _ ->
                (* The dependencies of dev tools are installed into the default
                 context so they may be shared with the project's
                 dependencies. *)
                Package_universe.Dependencies Context_name.default
              | _ -> package_universe
            in
            resolve db dep_loc dep_pkg_digest package_universe)
      and+ files_dir =
        let+ lock_dir_path =
          Package_universe.lock_dir_path package_universe >>| Option.value_exn
        and+ lock_dir = Package_universe.lock_dir package_universe in
        let version =
          Option.some_if (Dune_pkg.Lock_dir.uses_versioned_paths lock_dir) info.version
        in
        Dune_pkg.Lock_dir.Pkg.files_dir info.name version ~lock_dir:lock_dir_path
        |> Path.as_in_build_dir_exn
      in
      let* mounted =
        match package_universe with
        | Dev_tool _ -> Memo.return None
        | Dependencies context ->
          let* candidate = Pkg_sources.find_candidate context info.name in
          (match candidate with
           | None -> Memo.return None
           | Some candidate ->
             let+ selected = DB.project_pkg_digest context info.name in
             Option.some_if (Pkg_digest.equal pkg_digest selected) candidate)
      in
      let context = Package_universe.context_name package_universe in
      let kind =
        Memo.lazy_ ~name:"pkg-kind" (fun () ->
          match mounted with
          | None -> Memo.return `Opam
          | Some candidate ->
            Pkg_sources.find_mounted_kind context (Pkg_sources.Candidate.name candidate)
            >>| Option.map ~f:snd
            >>| Option.value ~default:`Opam)
      in
      let id = Pkg.Id.gen () in
      let write_paths =
        match mounted with
        | Some candidate -> candidate_paths candidate
        | None -> Paths.make pkg_digest package_universe
      in
      let install_command = choose_for_current_platform install_command in
      let install_command = Option.map install_command ~f:relocate in
      let build_command = choose_for_current_platform build_command in
      let build_command = Option.map build_command ~f:relocate_build in
      let paths =
        let paths = Paths.map_path write_paths ~f:Path.build in
        if
          (not (Pkg_toolchain.is_compiler_package_with_toolchains_enabled info.name))
          || is_compiler_version_relocatable info
          || has_relocatable_compiler_marker info depends
        then paths
        else (
          (* Modify the environment as well as build and install commands for
             the compiler package. The specific changes are:
             - setting the prefix in the build environment to inside the user's
               toolchain directory
             - changing the install command so that the
               package is installed with the DESTDIR variable set to a
               temporary directory, and the result is then moved to the user's
               toolchain directory
             - if a matching version of the compiler is
               already installed in the user's toolchain directory then the
               build and install commands are replaced with no-ops
             *)
          let prefix = Pkg_toolchain.installation_prefix pkg in
          let install_roots =
            Pkg_toolchain.install_roots ~prefix
            |> Install.Roots.map ~f:Path.outside_build_dir
          in
          { paths with
            prefix = Path.outside_build_dir prefix
          ; install_roots = Lazy.from_val install_roots
          ; install_paths =
              lazy
                (Install.Paths.make
                   ~relative:Path.relative
                   ~package:info.name
                   ~roots:install_roots)
          })
      in
      let t =
        { Pkg.id
        ; context
        ; kind
        ; build_command
        ; install_command
        ; depends
        ; depends_on_dune = has_dune_dep
        ; depexts
        ; lock_exported_env = exported_env
        ; paths
        ; write_paths
        ; info
        ; files_dir
        ; mounted
        ; exported_env = []
        }
      in
      let+ exported_env =
        let expander =
          Action_expander.expander_with_env
            (Package_universe.context_name package_universe)
            t
            ~env:Env.Map.empty
        in
        Memo.parallel_map exported_env ~f:(Action_expander.exported_env expander)
      in
      Some { t with exported_env }
  ;;

  let resolve =
    let memo =
      Memo.create
        "pkg-resolve"
        ~input:(module Input)
        ~human_readable_description:(fun t ->
          Pp.textf "- package %s" (Package.Name.to_string t.pkg_digest.name)
          |> Option.some)
        resolve_impl
    in
    fun (db : DB.t) loc pkg_digest package_universe ->
      Memo.exec memo { db; pkg_digest; universe = package_universe }
      >>| function
      | Some s -> s
      | None ->
        User_error.raise
          ~loc
          [ Pp.textf "Unknown package %S" (Package.Name.to_string pkg_digest.name) ]
  ;;
end

module Install_action = struct
  (* The install action does the following:

     1. Runs the install action in the lock file (if it exists)
     2. Reads the .install file produced by the build command
     3. Discovers all the files produced by 1.
     4. Combines the set of files in 2. and 3. to produce a "cookie" file
  *)

  let installable_sections =
    Section.(Set.diff all (Set.of_list [ Misc; Libexec; Libexec_root ]))
    |> Section.Set.to_list
  ;;

  module Spec = struct
    type ('path, 'target) t =
      { (* location of the install file we must read (if produced) *)
        install_file : 'path
      ; (* location of the variables we must read (if produced) *)
        config_file : 'path
      ; (* where we are supposed to put the installed artifacts *)
        target_dir : 'target
      ; (* if the package's installation prefix is outside the build
           dir, it's stored here and will be used instead of [target_dir]
           as the location of insntalled artifacts *)
        prefix_outside_build_dir : Path.Outside_build_dir.t option
      ; (* does the package have its own install command? *)
        install_action : [ `Has_install_action | `No_install_action ]
      ; package : Package.Name.t
      }

    let name = "install-file-run"
    let version = 2
    let runs_process = false
    let can_run_in_action_runner = false

    let bimap
          ({ install_file
           ; config_file
           ; target_dir
           ; prefix_outside_build_dir = _
           ; install_action = _
           ; package = _
           } as t)
          f
          g
      =
      { t with
        install_file = f install_file
      ; config_file = f config_file
      ; target_dir = g target_dir
      }
    ;;

    let is_useful_to_memoize = true

    let encode
          { install_file
          ; config_file
          ; target_dir
          ; prefix_outside_build_dir
          ; install_action
          ; package
          }
          path
          target
      : Sexp.t
      =
      List
        [ path install_file
        ; path config_file
        ; target target_dir
        ; (match
             Option.map
               prefix_outside_build_dir
               ~f:Path.Outside_build_dir.to_string_maybe_quoted
           with
           | None -> List []
           | Some s -> List [ Atom s ])
        ; Atom (Package.Name.to_string package)
        ; Atom
            (match install_action with
             | `Has_install_action -> "has_install_action"
             | `No_install_action -> "no_install_action")
        ]
    ;;

    let prepare_copy ~install_file ~target_dir entry =
      let dst =
        let paths =
          let package =
            Path.basename install_file
            |> Filename.remove_extension
            |> Filename.to_string
            |> Package.Name.of_string
          in
          let roots =
            Path.build target_dir
            |> Install.Roots.opam_from_prefix ~relative:Path.relative
          in
          Install.Paths.make ~relative:Path.relative ~package ~roots
        in
        Install.Entry.relative_installed_path entry ~paths
      in
      Path.mkdir_p (Path.parent_exn dst);
      dst
    ;;

    let collect_files ~root ~skip_dirs =
      List.iter skip_dirs ~f:(fun s -> assert (Path.equal root (Path.parent_exn s)));
      let path_of ~dir fname = Path.relative_fname (Path.relative root dir) fname in
      Fpath.traverse
        ~dir:(Path.to_string root)
        ~init:[]
        ~on_file:(fun ~dir fname acc -> path_of ~dir fname :: acc)
        ~enter_dir:(fun ~dir fname ->
          let path = path_of ~dir fname in
          not (List.mem skip_dirs path ~equal:Path.equal))
        ~on_error:
          (`Call
              (fun ~dir error acc ->
                if dir = "" then acc else Unix_error.Detailed.raise error))
        ()
    ;;

    let maybe_drop_sandbox_dir path =
      match Path.extract_build_context_dir_maybe_sandboxed path with
      | None -> path
      | Some (sandbox, source) ->
        let ctx =
          let name = Path.basename sandbox in
          Path.relative_fname (Path.build Path.Build.root) name
        in
        Path.append_source ctx source
    ;;

    let section_map_of_dir install_paths =
      (* reverse engineer the installed artifacts from running the install
         action by looking at the file system post running the action and
         taking educated guesses about which section each file belongs to *)
      let get = Install.Paths.get install_paths in
      List.concat_map installable_sections ~f:(fun section ->
        let path = get section in
        let files =
          match section with
          | Lib_root ->
            collect_files ~root:path ~skip_dirs:[ get Toplevel; get Stublibs; get Lib ]
          | Share_root -> collect_files ~root:path ~skip_dirs:[ get Share ]
          | _ -> collect_files ~root:path ~skip_dirs:[]
        in
        files
        |> List.rev_map ~f:(fun file ->
          let section =
            match
              match section with
              | Lib_root -> Some Section.Libexec_root
              | Lib -> Some Libexec
              | _ -> None
            with
            | None -> section
            | Some section' ->
              let perm =
                (Unix.stat (Path.to_string file)).st_perm |> Permissions.Mode.of_int
              in
              if Permissions.(test execute perm) then section' else section
          in
          section, maybe_drop_sandbox_dir file))
      |> Section.Map.of_list_multi
    ;;

    let maybe_set_executable section dst =
      match Section.should_set_executable_bit section with
      | false -> ()
      | true ->
        let dst = Path.to_string dst in
        let permission =
          let perm = (Unix.stat dst).st_perm |> Permissions.Mode.of_int in
          Permissions.(add execute) perm |> Permissions.Mode.to_int
        in
        Unix.chmod dst permission
    ;;

    let read_variables config_file =
      match Fpath.exists (Path.to_string config_file) with
      | false -> []
      | true ->
        let config =
          let filename = Path.to_string config_file in
          match
            Io.read_file_exn config_file
            |> OpamFile.Dot_config.read_from_string
                 ~filename:(OpamFile.make (OpamFilename.of_string filename))
          with
          | s -> s
          | exception OpamPp.Bad_format (pos, message) ->
            let loc =
              Option.map
                pos
                ~f:(fun { OpamParserTypes.FullPos.filename = _; start; stop } ->
                  let file_contents = Io.read_file_exn config_file in
                  let bols = ref [ 0 ] in
                  String.iteri file_contents ~f:(fun i ch ->
                    if ch = '\n' then bols := (i + 1) :: !bols);
                  let bols = Array.of_list (List.rev !bols) in
                  let make_pos (line, column) =
                    let pos_bol = bols.(line - 1) in
                    { Lexing.pos_fname = filename
                    ; pos_lnum = line
                    ; pos_bol
                    ; pos_cnum = pos_bol + column
                    }
                  in
                  let start = make_pos start in
                  let stop = make_pos stop in
                  Loc.create ~start ~stop)
            in
            let message_with_loc =
              (* The location is inlined b/c the original config file is going
                 to be deleted, so we don't be able to fetch the part of the
                 file that's bad *)
              let open Pp.O in
              let error =
                Pp.textf
                  "Error parsing %s"
                  (Path.basename config_file |> Filename.to_string)
              in
              match loc with
              | None -> error
              | Some loc ->
                (Loc.pp loc |> Pp.map_tags ~f:(fun Loc.Loc -> User_message.Style.Loc))
                ++ error
            in
            User_error.raise [ message_with_loc; User_error.reason (Pp.verbatim message) ]
        in
        OpamFile.Dot_config.bindings config
        |> List.map ~f:(fun (name, value) -> Package_variable_name.of_opam name, value)
    ;;

    (* On Windows, .install files may omit .exe for bin/sbin entries.
       Try the .exe variant if the original doesn't exist, mirroring opam. *)
    let maybe_add_exe src (entry : Path.t Install.Entry.Expanded.t) =
      match
        match Sys.win32, entry.section with
        | true, (Bin | Sbin) when not (Fpath.exists (Path.to_string src)) ->
          let src_exe_str = Bin.add_exe (Path.to_string src) in
          if Fpath.exists src_exe_str then Some src_exe_str else None
        | _ -> None
      with
      | None -> src, entry
      | Some src_exe_str ->
        ( Path.of_string src_exe_str
        , Install.Entry.map_dst entry ~f:Install.Entry.Dst.maybe_add_exe )
    ;;

    let install_entry
          ~src
          ~install_file
          ~target_dir
          (entry : Path.t Install.Entry.Expanded.t)
      =
      let src, entry = maybe_add_exe src entry in
      match Fpath.exists (Path.to_string src), entry.optional with
      | false, true -> None
      | false, false ->
        User_error.raise
          (* TODO loc *)
          [ Pp.textf
              "entry %s in %s does not exist"
              (Path.to_string_maybe_quoted src)
              (Path.to_string install_file)
          ]
      | true, _ ->
        let dst = prepare_copy ~install_file ~target_dir entry in
        (let src =
           match Path.to_string src |> Unix.readlink with
           | exception Unix.Unix_error (_, _, _) -> src
           | link ->
             Path.external_
               (let base = Path.parent_exn src in
                Filename.concat (Path.to_absolute_filename base) link
                |> Path.External.of_string)
         in
         Io.portable_hardlink ~overwrite:true ~src ~dst);
        maybe_set_executable entry.section dst;
        Some (entry.section, dst)
    ;;

    let resolve_symlinks_in root =
      let on_symlink ~dir fname () =
        let path = Filename.concat root (Filename.append dir fname) in
        match Fpath.follow_symlink path with
        | Error (Unix_error e) -> Unix_error.Detailed.raise e
        | Error Not_a_symlink ->
          Code_error.raise
            "resolve_symlinks_in: not a symlink"
            [ "path", Dyn.string path ]
        | Error Max_depth_exceeded ->
          User_error.raise
            [ Pp.textf
                "Unable to resolve symlink %s: too many levels of symbolic links"
                path
            ]
        | Ok resolved ->
          (match Unix.lstat resolved with
           | { Unix.st_kind = S_REG; _ } ->
             (* CR-someday rgrinberg: pass chmod:true here? *)
             Fpath.unlink_exn path;
             Io.portable_hardlink
               ~overwrite:true
               ~src:(Path.of_string resolved)
               ~dst:(Path.of_string path)
           | _ -> ());
          (), None
      in
      Fpath.traverse
        ~dir:root
        ~init:()
        ~on_other:`Ignore
        ~on_symlink:(`Call on_symlink)
        ()
    ;;

    let action
          { package
          ; install_file
          ; config_file
          ; target_dir
          ; prefix_outside_build_dir
          ; install_action
          }
          ~ectx:_
          ~eenv:_
      =
      let open Fiber.O in
      let* () = Fiber.return () in
      let* files =
        let from_install_action =
          let target_dir =
            (* If the package used a prefix that was outside the build
               directory (as is the case with toolchains), parse the
               installed sections from that location. Otherwise parse the
               installed sections from the package's location within the
               build directory. *)
            match prefix_outside_build_dir with
            | Some prefix_outside_build_dir ->
              Path.outside_build_dir prefix_outside_build_dir
            | None -> Path.build target_dir
          in
          match install_action with
          | `No_install_action -> Section.Map.empty
          | `Has_install_action ->
            let install_paths =
              let roots =
                Install.Roots.opam_from_prefix ~relative:Path.relative target_dir
              in
              Install.Paths.make ~relative:Path.relative ~package ~roots
            in
            section_map_of_dir install_paths
        in
        let+ from_install_file =
          (* Read all the artifacts from the .install file produced by
             the build command. This is the happy path where we don't guess
             anything. *)
          Async.async (fun () -> Fpath.exists (Path.to_string install_file))
          >>= function
          | false -> Fiber.return Section.Map.empty
          | true ->
            let* map =
              let install_entries =
                let dir = Path.parent_exn install_file in
                Install.Entry.Expanded.load_install_file install_file (fun local ->
                  Path.append_local dir local)
              in
              let by_src =
                List.rev_map install_entries ~f:(fun (entry : _ Install.Entry.t) ->
                  entry.src, entry)
                |> Path.Map.of_list_multi
              in
              let+ install_entries =
                Path.Map.to_list_map by_src ~f:(fun src entries ->
                  List.map entries ~f:(fun entry -> src, entry))
                |> List.concat
                |> Fiber.parallel_map ~f:(fun (src, entry) ->
                  Async.async (fun () ->
                    install_entry ~src ~install_file ~target_dir entry))
                >>| List.filter_opt
              in
              List.rev_map install_entries ~f:(fun (section, file) ->
                let file = maybe_drop_sandbox_dir file in
                section, file)
              |> Section.Map.of_list_multi
            in
            let+ () =
              Async.async (fun () ->
                (* CR-someday rgrinberg: pass chmod:true here? *)
                Fpath.unlink_exn (Path.to_string install_file))
            in
            map
        in
        let declared =
          Section.Map.values from_install_file |> List.concat |> Path.Set.of_list
        in
        let from_install_action =
          Section.Map.map from_install_action ~f:(fun files ->
            List.filter files ~f:(fun file -> not (Path.Set.mem declared file)))
        in
        Section.Map.union from_install_action from_install_file ~f:(fun _ x y ->
          Some (x @ y))
        |> Section.Map.map ~f:(List.sort_uniq ~compare:Path.compare)
      in
      let* cookies =
        let+ variables = Async.async (fun () -> read_variables config_file) in
        { Install_cookie.Gen.files; variables }
      in
      Async.async (fun () ->
        (* Resolve symlinks in target_dir so that the cache can store them. The
         dune cache doesn't support symlinks, so we replace them with hardlinks
         to their targets. *)
        if Fpath.exists (Path.Build.to_string target_dir)
        then resolve_symlinks_in (Path.Build.to_string target_dir);
        (* Produce the cookie file in the standard path *)
        let cookie_file = Path.build @@ Paths.install_cookie' target_dir in
        cookie_file |> Path.parent_exn |> Path.mkdir_p;
        Install_cookie.dump cookie_file cookies)
    ;;
  end

  module A = Action_ext.Make (Spec)

  let action (p : Path.Build.t Paths.t) install_action ~prefix_outside_build_dir =
    A.action
      { Spec.install_file = Path.build @@ Paths.install_file p
      ; config_file = Path.build @@ Paths.config_file p
      ; target_dir = p.target_dir
      ; prefix_outside_build_dir
      ; install_action
      ; package = p.name
      }
  ;;
end

module Copy_source = struct
  module Spec = struct
    type ('path, 'target) t = 'path * 'target

    let name = "copy-package-source"
    let version = 1
    let is_useful_to_memoize = true
    let runs_process = false
    let can_run_in_action_runner = false
    let bimap (src, dst) f g = f src, g dst
    let encode (src, dst) input output = Sexp.List [ input src; output dst ]

    let action (src, dst) ~ectx:_ ~eenv:_ =
      Async.async (fun () ->
        Io.copy_file
          ~overwrite:true
          ~chmod:(Permissions.add Permissions.write)
          ~src
          ~dst:(Path.build dst)
          ())
    ;;
  end

  include Action_ext.Make (Spec)
end

let copy_source_input source ~dst =
  let open Action_builder.O in
  let* { Source_input.files; directories } = source in
  let+ () = Action_builder.paths (List.map files ~f:fst) in
  Action.progn
    (List.map (Path.Local.root :: directories) ~f:(fun local ->
       Action.mkdir (Path.Build.append_local dst local))
     @ List.map files ~f:(fun (src, local) ->
       let dst = Path.Build.append_local dst local in
       Action.progn
         [ Action.mkdir (Path.Build.parent_exn dst)
         ; Action.remove_tree dst
         ; Copy_source.action (src, dst)
         ]))
;;

let execute ~expander ~write_paths ~source ~build ~install =
  let copies = Action_builder.map source ~f:Action.Full.make in
  let install_dirs =
    match install with
    | [] -> []
    | _ ->
      let paths = Paths.install_paths write_paths in
      [ Install_action.installable_sections
        |> List.map ~f:(fun section -> Action.mkdir (Install.Paths.get paths section))
        |> Action.progn
        |> Action.Full.make
        |> Action_builder.With_targets.return
      ]
  in
  let finish =
    Install_action.action
      write_paths
      (match install with
       | [] -> `No_install_action
       | _ -> `Has_install_action)
      ~prefix_outside_build_dir:
        (Path.as_outside_build_dir expander.Action_expander.Expander.paths.prefix)
    |> Action.Full.make
    |> Action_builder.With_targets.return
  in
  Action_builder.progn
    ((Action_builder.with_no_targets copies :: build)
     @ install_dirs
     @ install
     @ [ finish ])
  |> Action_builder.With_targets.map ~f:(fun action ->
    Action.Full.add_env (Value_list_env.to_env expander.env) action
    |> Action.Full.add_sandbox (Sandbox_mode.Set.singleton Sandbox_mode.copy)
    |> Action.Full.disable_sandbox_policy)
  |> Action_builder.With_targets.add_directories
       ~directory_targets:[ write_paths.target_dir ]
;;

let execute_recipe ~build ~install ~expander ~write_paths ~source =
  let { Action_expander.Expander.paths; _ } = expander in
  let expand action =
    let+ action = Action_expander.expand_action action ~expander in
    Action.chdir paths.source_dir action
    |> Action.Full.make
    |> Action_builder.With_targets.return
  in
  let* build =
    match build with
    | None -> Memo.return []
    | Some (Build_command.Action action) -> expand action >>| List.singleton
    | Some Dune ->
      Command.run_dyn_prog
        (Action_builder.return (Ok (Path.of_string Sys.executable_name)))
        ~dir:paths.source_dir
        [ A "build"; A "-p"; A (Package.Name.to_string paths.name) ]
      |> List.singleton
      |> Memo.return
  and* install =
    match install with
    | None -> Memo.return []
    | Some action -> expand action >>| List.singleton
  in
  execute ~expander ~write_paths ~source ~build ~install |> Memo.return
;;

let add_env env action =
  Action_builder.With_targets.map action ~f:(Action.Full.add_env env)
;;

let rule ?loc { Action_builder.With_targets.build; targets } =
  (* TODO this ignores the workspace file *)
  Rule.make ~info:(Rule.Info.of_loc_opt loc) ~targets build |> Rules.Produce.rule
;;

let source_files root ~loc =
  let skip_dir = function
    | ".hg" | ".git" | "_darcs" | "_opam" | "_build" | "_esy" -> true
    | _ -> false
  in
  let skip_file = String.starts_with ~prefix:".#" in
  let rec loop acc path =
    let full_path = Path.Outside_build_dir.append_local root path in
    Fs_memo.dir_contents full_path
    >>= function
    | Error e ->
      Memo.return
        (Error
           (User_error.make
              ~loc
              [ Pp.textf
                  "Unable to read %s"
                  (Path.Outside_build_dir.to_string_maybe_quoted full_path)
              ; Unix_error.Detailed.pp e
              ]))
    | Ok contents ->
      let files, dirs =
        let contents = Fs_memo.Dir_contents.to_list contents in
        List.rev_filter_partition_map contents ~f:(fun (name, kind) ->
          (* TODO handle links and cycles correctly *)
          let name_s = Filename.to_string name in
          let relative = Path.Local.relative_fname path name in
          match kind with
          | S_DIR -> if skip_dir name_s then Skip else Right relative
          | _ -> if skip_file name_s then Skip else Left relative)
      in
      let acc = Path.Local.Set.of_list files |> Path.Local.Set.union acc in
      Memo.map_reduce
        dirs
        ~f:(loop Path.Local.Set.empty)
        ~empty:(Ok acc)
        ~combine:(fun left right ->
          let open Result.O in
          let* left = left in
          let+ right = right in
          Path.Local.Set.union left right)
  in
  loop Path.Local.Set.empty Path.Local.root
;;

let source_rules (paths : Path.Build.t Paths.t) (info : Pkg_info.t) =
  let+ source_deps, copy_rules =
    match info.source with
    | None -> Memo.return (Ok Dep.Set.empty, [])
    | Some source ->
      let loc = fst source.url in
      Lock_dir.source_kind source
      >>= (function
       | Error error -> Memo.return (Error error, [])
       | Ok (`Local (`File, _) | `Fetch) ->
         let fetch =
           Fetch_rules.fetch ~target:paths.source_dir Dir source
           |> With_targets.map
                ~f:
                  (Action.Full.map ~f:(fun action ->
                     let progress =
                       Pkg_build_progress.progress_action
                         info.name
                         info.version
                         `Downloading
                     in
                     Action.progn [ progress; action ]))
         in
         Memo.return
           (Ok (Dep.Set.of_files [ Path.build paths.source_dir ]), [ loc, fetch ])
       | Ok (`Local (`Directory, source_root)) ->
         source_files source_root ~loc
         >>| (function
          | Error error -> Error error, []
          | Ok files ->
            let source_root = Path.outside_build_dir source_root in
            let source_files, rules =
              Path.Local.Set.fold
                files
                ~init:([], [])
                ~f:(fun file (source_files, rules) ->
                  let src = Path.append_local source_root file in
                  if Path.is_broken_symlink src
                  then
                    (* Don't copy broken symlinks into the build directory. Note
                       that this only works for packages sourced from local
                       directories. Packages whose source is extracted from an
                       archive (possibly fetched over the web) have broken symlinks
                       explicitly deleted immediately after the archive is
                       extracted. This logic is implemented in
                       [Fetch.resolve_directory_symlinks]. *)
                    source_files, rules
                  else (
                    let dst = Path.Build.append_local paths.source_dir file in
                    let copy = loc, Action_builder.copy ~src ~dst in
                    Path.build dst :: source_files, copy :: rules))
            in
            Ok (Dep.Set.of_files source_files), rules))
  in
  let extra_source_deps, extra_copy_rules =
    List.map info.extra_sources ~f:(fun (local, (fetch : Source.t)) ->
      let extra_source = Paths.extra_source_build paths local in
      let loc = fst fetch.url in
      let rule =
        (* We assume that [fetch] is always a file. Would be good
           to give a decent error message if it's not *)
        match Source.kind fetch with
        | `Directory_or_archive src ->
          Action_builder.copy ~src:(Path.external_ src) ~dst:extra_source
        | `Fetch -> Fetch_rules.fetch ~target:extra_source File fetch
      in
      Path.build extra_source, (loc, rule))
    |> List.unzip
  in
  let copy_rules = copy_rules @ extra_copy_rules in
  let source_deps =
    let open Action_builder.O in
    let+ () = Action_builder.return () in
    Dep.Set.union (User_error.ok_exn source_deps) (Dep.Set.of_files extra_source_deps)
  in
  source_deps, Memo.parallel_iter copy_rules ~f:(fun (loc, copy) -> rule ~loc copy)
;;

let rec scan_contents p =
  let module P = Path.Build in
  let dir_contents =
    match Readdir.read_directory_with_kinds (P.to_string p) with
    | Error (Unix.ENOENT, _, _) ->
      (* Directory doesn't exist - package has no extra files *)
      []
    | Ok dir_contents -> dir_contents
    | Error e ->
      Code_error.raise
        "Failure to enumerate files"
        [ "error", Unix_error.Detailed.to_dyn e ]
  in
  List.fold_left
    dir_contents
    ~init:(P.Set.empty, P.Set.empty)
    ~f:(fun (files, empty_directories) (file_name, file_kind) ->
      let p = P.relative_fname p file_name in
      match (file_kind : Unix.file_kind) with
      | S_REG -> P.Set.add files p, empty_directories
      | S_DIR ->
        let recursive_files, recursive_empty_dir = scan_contents p in
        (match P.Set.is_empty recursive_files, P.Set.is_empty recursive_empty_dir with
         | true, true ->
           recursive_files, P.Set.union empty_directories recursive_empty_dir
         | true, false -> files, P.Set.union empty_directories recursive_empty_dir
         | false, _ -> P.Set.union files recursive_files, empty_directories)
      | otherwise ->
        Code_error.raise
          "Unsupported directory content"
          [ "path", P.to_dyn p; "file_kind", File_kind.to_dyn otherwise ])
;;

let files path =
  let files, empty_directories = scan_contents path in
  let to_path_set set =
    Path.Build.Set.fold
      set
      ~f:(fun e acc -> Path.Set.add acc (Path.build e))
      ~init:Path.Set.empty
  in
  let files = to_path_set files in
  let empty_directories = to_path_set empty_directories in
  Dep.Set.of_source_files ~files ~empty_directories, files
;;

let dune_dep =
  lazy (Sys.executable_name |> Path.External.of_string |> Path.external_ |> Dep.file)
;;

(* The fetched source of a package with its lock directory files and extra
   sources laid over it. *)
let source_input ~source ~files_dir ~extra_sources =
  let open Action_builder.O in
  let+ files =
    Action_builder.of_memo
      (Memo.of_thunk (fun () ->
         let deps, files = files files_dir in
         Memo.return (files, deps)))
    |> Action_builder.dyn_deps
  in
  let files =
    source.Source_input.files
    @ Path.Set.to_list_map files ~f:(fun src ->
      src, Path.drop_prefix_exn src ~prefix:(Path.build files_dir))
    @ extra_sources
  in
  { source with files }
;;

let candidate_source_input candidate =
  let open Action_builder.O in
  let* source = Action_builder.of_memo (Pkg_sources.source candidate) in
  source_input
    ~source
    ~files_dir:(Pkg_sources.Candidate.files_dir candidate)
    ~extra_sources:
      (List.map
         (Pkg_sources.Candidate.lock_pkg candidate).info.extra_sources
         ~f:(fun (local, source) ->
           let path =
             match Dune_pkg.Source.kind source with
             | `Directory_or_archive path -> Path.external_ path
             | `Fetch -> Fetch_rules.make_target ~kind:File source |> Path.build
           in
           path, local))
;;

let prepared_source_rule candidate ~target ~patches =
  let build =
    let open Action_builder.O in
    let+ copies = copy_source_input (candidate_source_input candidate) ~dst:target in
    let patches =
      List.map patches ~f:(fun (_loc, patch) ->
        Dune_patch.action ~patch:(Path.build (Path.Build.append_local target patch))
        |> Action.chdir (Path.build target))
    in
    Action.progn (copies :: patches)
    |> Action.Full.make ~sandbox:Sandbox_config.needs_sandboxing
  in
  Action_builder.with_no_targets build
  |> Action_builder.With_targets.add_directories ~directory_targets:[ target ]
  |> rule
       ~loc:
         (match patches with
          | (loc, _) :: _ -> Dune_pkg.Lock_dir.loc_in_source_tree loc
          | [] -> Loc.none)
;;

let gen_prepared_source_rules context ~dir components =
  let module Gen_rules = Build_config.Gen_rules in
  match components with
  | [] -> Gen_rules.make_empty ~dir Subdir_set.all |> Memo.return
  | [ name ] ->
    let name = Package.Name.of_string name in
    let+ candidate = Pkg_sources.find_candidate context name
    and+ preparation = Pkg_sources.preparation context name in
    (match
       ( candidate
       , match preparation with
         | None | Some Opaque -> None
         | Some (Plain _) -> Some []
         | Some (Prepared { patches; rest = _; native = _ }) -> Some patches )
     with
     | Some candidate, Some patches ->
       let target = Pkg_sources.prepared_source context name in
       Gen_rules.make
         ~directory_targets:(Path.Build.Map.singleton target Loc.none)
         (Rules.collect_unit (fun () -> prepared_source_rule candidate ~target ~patches))
     | _ -> Gen_rules.no_rules)
  | _ -> Gen_rules.Redirect_to_parent Gen_rules.Rules.empty |> Memo.return
;;

let build_rule context_name ~source_deps (pkg : Pkg.t) =
  let* exported_env = Pkg.exported_env pkg in
  let+ build_action =
    let+ copy_action, build_action, install_action =
      let+ copy_action =
        let+ copy_action =
          let+ () = Memo.return () in
          let open Action_builder.O in
          [ Action_builder.with_no_targets
            @@ (Action_builder.of_memo
                  (Memo.of_thunk (fun () ->
                     let deps, source_deps = files pkg.files_dir in
                     Memo.return (source_deps, deps)))
                |> Action_builder.dyn_deps
                >>= fun source_deps ->
                Path.Set.to_list_map source_deps ~f:(fun src ->
                  let dst =
                    let prefix = Path.build pkg.files_dir in
                    let local_path = Path.drop_prefix_exn src ~prefix in
                    Path.Build.append_local pkg.write_paths.source_dir local_path
                  in
                  Action.progn
                    [ Action.mkdir (Path.Build.parent_exn dst); Action.copy src dst ])
                |> Action.concurrent
                |> Action.Full.make
                |> Action_builder.return)
          ]
        in
        copy_action
        @ List.map pkg.info.extra_sources ~f:(fun (local, _) ->
          (* If the package has extra sources, they will be
             initially stored in the extra_sources directory for that
             package. Prior to building, the contents of
             extra_sources must be copied into the package's source
             directory. *)
          let src = Paths.extra_source pkg.paths local in
          let dst = Path.Build.append_local pkg.write_paths.source_dir local in
          Action.progn
            [ (* If the package has no source directory (some
                 low-level packages are exclusively made up of extra
                 sources), the source directory is first created. *)
              Action.mkdir pkg.write_paths.source_dir
            ; (* It's possible for some extra sources to already be at
                 the destination. If these files are write-protected
                 then the copy action will fail if we don't first remove
                 them. *)
              Action.remove_tree dst
            ; Action.copy src dst
            ]
          |> Action.Full.make
          |> Action_builder.With_targets.return)
      and+ build_action =
        match Action_expander.build_command context_name pkg with
        | None -> Memo.return []
        | Some build_command -> build_command >>| List.singleton
      and+ install_action =
        match Action_expander.install_command context_name pkg with
        | None -> Memo.return []
        | Some install_action ->
          let+ install_action = install_action in
          let mkdir_install_dirs =
            let install_paths = Paths.install_paths pkg.write_paths in
            Install_action.installable_sections
            |> List.rev_map ~f:(fun section ->
              Install.Paths.get install_paths section |> Action.mkdir)
            |> Action.progn
            |> Action.Full.make
            |> Action_builder.With_targets.return
          in
          [ mkdir_install_dirs; install_action ]
      in
      copy_action, build_action, install_action
    in
    let install_file_action =
      let prefix_outside_build_dir = Path.as_outside_build_dir pkg.paths.prefix in
      Install_action.action
        pkg.write_paths
        (match Action_expander.install_command context_name pkg with
         | None -> `No_install_action
         | Some _ -> `Has_install_action)
        ~prefix_outside_build_dir
      |> Action.Full.make
      |> Action_builder.return
      |> Action_builder.with_no_targets
    in
    (* Action to print a "Building" message for the package if its
       target directory is not yet created. *)
    let progress_building =
      Pkg_build_progress.progress_action pkg.info.name pkg.info.version `Building
      |> Action.Full.make
      |> Action_builder.return
      |> Action_builder.with_no_targets
    in
    [ copy_action
    ; [ progress_building ]
    ; build_action
    ; install_action
    ; [ install_file_action ]
    ]
    |> List.concat
    |> Action_builder.progn
  in
  let open Action_builder.With_targets.O in
  (let deps =
     let open Action_builder.O in
     let+ source_deps = source_deps in
     let deps =
       match pkg.depends_on_dune with
       | false -> source_deps
       | true -> Dep.Set.add source_deps (Lazy.force dune_dep)
     in
     (), deps
   in
   Action_builder.O.(Action_builder.dyn_deps deps >>> Pkg.package_deps pkg)
   |> Action_builder.with_no_targets)
  (* TODO should we add env deps on these? *)
  >>> add_env exported_env build_action
  |> Action_builder.With_targets.map ~f:Action.Full.disable_sandbox_policy
  |> Action_builder.With_targets.add_directories
       ~directory_targets:[ pkg.write_paths.target_dir ]
;;

let gen_rules ({ DB.pkg_digest_table; _ } as db) ~package_universe pkg_digest =
  let { DB.Pkg_table.pkg = { info; _ }; _ } =
    Pkg_digest.Map.find_exn pkg_digest_table pkg_digest
  in
  let paths = Paths.make pkg_digest package_universe in
  let* source_deps, copy_rules = source_rules paths info in
  let build =
    let open Action_builder.O in
    let* { With_targets.build; targets = _ } =
      let context_name = Package_universe.context_name package_universe in
      let* pkg =
        Resolve.resolve db Loc.none pkg_digest package_universe |> Action_builder.of_memo
      in
      build_rule context_name pkg ~source_deps |> Action_builder.of_memo
    in
    build
  in
  let build_rule =
    Action_builder.with_no_targets build
    |> Action_builder.With_targets.add_directories ~directory_targets:[ paths.target_dir ]
  in
  let* () = copy_rules
  and* () = rule ~loc:Loc.none (* TODO *) build_rule in
  Memo.return ()
;;

module Gen_rules = Build_config.Gen_rules

let pkg_alias_disabled =
  Action_builder.fail
    { fail =
        (fun () ->
          let error =
            [ Pp.text "The @pkg-install alias cannot be used without a lock dir" ]
          in
          let hints =
            [ Pp.concat
                ~sep:Pp.space
                [ Pp.text "You might want to create the lock dir with"
                ; User_message.command "dune pkg lock"
                ]
            ]
          in
          User_error.raise ~hints error)
    }
;;

let setup_pkg_install_alias =
  let build_packages_of_context ctx_name =
    (* Fetching the package target implies that we will also fetch the extra
       sources. *)
    let open Action_builder.O in
    let* packages =
      Action_builder.of_memo
        (let open Memo.O in
         let* db = DB.of_ctx ctx_name ~allow_sharing:false in
         Pkg_digest.Map.values db.pkg_digest_table
         |> Memo.parallel_map ~f:(fun { DB.Pkg_table.pkg_digest; _ } ->
           Resolve.resolve db Loc.none pkg_digest (Dependencies ctx_name)))
    in
    Pkg.deps ctx_name packages
  in
  fun ~dir ctx_name ->
    (* We only need to build when the build_dir is the root of the context *)
    match
      let build_dir = Context_name.build_dir ctx_name in
      Path.Build.equal dir build_dir
    with
    | false -> Gen_rules.no_rules
    | true ->
      let rule =
        let* active = Lock_dir.lock_dir_active ctx_name in
        let alias = Alias.make ~dir Alias0.pkg_install in
        Rules.collect_unit (fun () ->
          let deps =
            match active with
            | true -> build_packages_of_context ctx_name
            | false -> pkg_alias_disabled
          in
          Rules.Produce.Alias.add_deps alias deps)
      in
      Gen_rules.make
        ~build_dir_only_sub_dirs:
          (Gen_rules.Build_only_sub_dirs.singleton ~dir Subdir_set.empty)
        rule
;;

let setup_package_rules db ~package_universe pkg_digests : Gen_rules.t Memo.t =
  let+ rules =
    Rules.collect_unit (fun () ->
      Memo.parallel_iter pkg_digests ~f:(gen_rules db ~package_universe))
  in
  Gen_rules.make ~directory_targets:(Rules.directory_targets rules) (Memo.return rules)
;;

let setup_rules ~components ~dir ctx =
  (* Note that the path components in the following patterns must
     correspond to the paths returned by [Paths.make]. The string
     ".dev-tool" is hardcoded into several patterns, and must match
     the value of [Pkg_dev_tool.install_path_base_dir_name]. *)
  assert (String.equal Pkg_dev_tool.install_path_base_dir_name ".dev-tool");
  match Context_name.is_default ctx, components with
  | true, [ ".dev-tool"; dev_tool_package_name ] ->
    let pkg_name = Package.Name.of_string dev_tool_package_name in
    let dev_tool = Pkg_dev_tool.of_package_name pkg_name in
    let* db, pkg_digest = DB.of_dev_tool (Dune_pkg.Dev_tool.of_package_name pkg_name) in
    setup_package_rules db ~package_universe:(Dev_tool dev_tool) [ pkg_digest ]
  | true, [ ".dev-tool" ] -> Gen_rules.make_empty ~dir Subdir_set.all |> Memo.return
  | _, [ ".pkg" ] ->
    (* Only generate pkg rules if there is a lock dir for that context *)
    let* lock_dir_active = Lock_dir.lock_dir_active ctx in
    (match lock_dir_active with
     | false -> Memo.return @@ Gen_rules.make (Memo.return Rules.empty)
     | true ->
       let* db = DB.of_ctx ctx ~allow_sharing:true in
       (* Project packages are mounted: only what is left, the unshared
          dependencies of dev tools, is built here. Told from the lock
          directory alone, so that nothing is resolved to generate rules. *)
       let* project = Memo.exec DB.Pkg_table.project_entries ctx in
       let project =
         Package.Name.Map.values project
         |> Pkg_digest.Set.of_list_map ~f:(fun (entry : DB.Pkg_table.entry) ->
           entry.pkg_digest)
       in
       setup_package_rules
         db
         ~package_universe:(Dependencies ctx)
         (Pkg_digest.Map.keys db.pkg_digest_table
          |> List.filter ~f:(fun digest -> not (Pkg_digest.Set.mem project digest))))
  | _, ".pkg" :: _ :: _ ->
    Memo.return (Gen_rules.Redirect_to_parent Gen_rules.Rules.empty)
  | true, ".dev-tool" :: _ :: _ :: _ ->
    Memo.return (Gen_rules.Redirect_to_parent Gen_rules.Rules.empty)
  | is_default, [] ->
    let sub_dirs =
      Filename.pkg_dir_basename
      :: (if is_default then [ Filename.dev_tool_dir_basename ] else [])
    in
    let build_dir_only_sub_dirs =
      Gen_rules.Build_only_sub_dirs.singleton ~dir @@ Subdir_set.of_list sub_dirs
    in
    Memo.return @@ Gen_rules.make ~build_dir_only_sub_dirs (Memo.return Rules.empty)
  | _ -> Memo.return Gen_rules.no_rules
;;

let resolve_pkg_dep context (loc, package_name) =
  let* db, pkg_digest = DB.of_project_pkg context package_name in
  Resolve.resolve db loc pkg_digest (Dependencies context)
;;

let dependency context name =
  let+ pkg = resolve_pkg_dep context (Loc.none, name) in
  Pkg.dependency pkg
;;

let find_opaque context name =
  let* mounted = Pkg_sources.find_mounted_kind context name in
  match mounted with
  | None | Some (_, `Dune) -> Memo.return None
  | Some (mounted, `Opam) ->
    let candidate = Pkg_sources.Mounted.candidate mounted in
    let root = (candidate_paths candidate).target_dir in
    let+ dependency = dependency context name in
    Some (root, dependency)
;;

let gen_mounted_rule context candidate ~dependencies =
  let name = Pkg_sources.Candidate.name candidate in
  let* pkg = resolve_pkg_dep context (Loc.none, name)
  and* preparation = Pkg_sources.preparation context name
  and* backing = Pkg_sources.mount_backing context name in
  (* A mounted source already has the recipe's leading patches applied. *)
  let build =
    match preparation, pkg.build_command with
    | Some (Prepared { rest; patches = _; native = _ }), Some (Action _) ->
      Some (Build_command.Action (Progn rest))
    | _, build -> build
  in
  let source =
    let open Action_builder.O in
    match backing with
    | None -> Action_builder.return (Action.mkdir pkg.write_paths.source_dir)
    | Some backing ->
      let* { Source_input.files; directories = _ } =
        Action_builder.of_memo
          (Pkg_sources.listing ~loc:(Pkg_sources.Candidate.source_loc candidate) backing)
      in
      let+ () =
        List.map files ~f:(fun (_, local) ->
          Path.build (Path.Build.append_local pkg.write_paths.source_dir local))
        |> Action_builder.paths
      in
      Action.progn []
  in
  let expander =
    let open Action_builder.O in
    let* direct, layout = dependencies in
    let path = Env_path.path (Global.env ()) in
    let+ env =
      match Layout.dependencies layout with
      | [] -> Action_builder.return (Global.env ())
      | _ -> layout_env layout ~path ~base:(Global.env ())
    in
    Action_expander.for_recipe
      pkg
      ~context
      ~path
      ~env
      ~direct
      ~dependencies:(Layout.dependencies layout)
  in
  let progress =
    Pkg_build_progress.progress_action pkg.info.name pkg.info.version `Building
    |> Action.Full.make
    |> Action_builder.With_targets.return
  in
  let build =
    let open Action_builder.O in
    let* expander = expander in
    let* action =
      Action_builder.of_memo
        (execute_recipe
           ~build
           ~install:pkg.install_command
           ~expander
           ~write_paths:pkg.write_paths
           ~source)
    in
    let* () =
      if pkg.depends_on_dune
      then Action_builder.deps (Dep.Set.singleton (Lazy.force dune_dep))
      else Action_builder.return ()
    in
    let { Action_builder.With_targets.build; targets = _ } =
      Action_builder.progn [ progress; action ]
    in
    build
  in
  Action_builder.with_no_targets build
  |> Action_builder.With_targets.add_directories
       ~directory_targets:[ pkg.write_paths.target_dir ]
  |> rule ~loc:Loc.none
;;

let ocaml_toolchain context =
  Memo.push_stack_frame ~human_readable_description:(fun () ->
    Pp.textf
      "Loading OCaml toolchain from Lock directory for context %S"
      (Context_name.to_string context))
  @@ fun () ->
  let* lock_dir = Lock_dir.get_exn context in
  match lock_dir.ocaml with
  | None -> Memo.return None
  | Some ocaml ->
    let+ pkg = resolve_pkg_dep context ocaml in
    let toolchain =
      let open Action_builder.O in
      let transitive_deps = pkg :: Pkg.deps_closure pkg in
      let* env, binaries =
        Action_builder.List.fold_left
          ~init:(Global.env (), Path.Set.empty)
          ~f:(fun (env, binaries) pkg ->
            let* pkg_env = Action_builder.of_memo (Pkg.exported_env pkg) in
            let env = Env.extend_env env pkg_env in
            let+ cookie = Install_cookie.read pkg.paths in
            let binaries =
              Section.Map.find cookie.files Bin
              |> Option.value ~default:[]
              |> Path.Set.of_list
              |> Path.Set.union binaries
            in
            env, binaries)
          transitive_deps
      in
      let path = Env_path.path (Global.env ()) in
      Action_builder.of_memo @@ Ocaml_toolchain.of_binaries ~path context env binaries
    in
    Some (Action_builder.memoize "ocaml_toolchain" toolchain)
;;

(* Every caller must get the same memoized builder: building the toolchain runs
   the compiler to read its configuration. *)
let ocaml_toolchain =
  let memo =
    Memo.create "pkg-ocaml-toolchain" ~input:(module Context_name) ocaml_toolchain
  in
  Memo.exec memo
;;

let all_deps universe =
  let* db =
    match (universe : Package_universe.t) with
    | Dependencies ctx ->
      (* Disallow sharing so that the only packages in the DB are the ones from
         the universe's respective lock directory. *)
      DB.of_ctx ctx ~allow_sharing:false
    | Dev_tool tool -> DB.of_dev_tool tool >>| fst
  in
  Pkg_digest.Map.values db.pkg_digest_table
  |> Memo.parallel_map ~f:(fun { DB.Pkg_table.pkg_digest; _ } ->
    Resolve.resolve db Loc.none pkg_digest universe)
  >>| Pkg.top_closure
;;

let all_project_deps context = all_deps (Dependencies context)

let project_deps ~(packages : Package.Name.Selection.t) context =
  let+ all_project_deps = all_project_deps context in
  match packages with
  | All -> all_project_deps
  | Only packages ->
    List.filter all_project_deps ~f:(fun (pkg : Pkg.t) ->
      Package.Name.Set.mem packages pkg.info.name)
;;

let describe_packages : Package.Name.Selection.t -> string = function
  | All -> "all packages"
  | Only packages ->
    Package.Name.Set.to_list packages
    |> List.map ~f:Package.Name.to_string
    |> String.concat ~sep:", "
;;

module Context_and_packages = struct
  type t = Context_name.t * Package.Name.Selection.t

  let to_dyn = Tuple.T2.to_dyn Context_name.to_dyn Package.Name.Selection.to_dyn
  let equal = Tuple.T2.equal Context_name.equal Package.Name.Selection.equal
  let hash = Tuple.T2.hash Context_name.hash Package.Name.Selection.hash
end

(* The package installing the compiler and its dependencies. Their binaries
   are visible from every directory, whatever it declares. *)
let compiler_packages =
  let memo =
    Memo.create
      "compiler-packages"
      ~input:(module Context_name)
      (fun context ->
         let* lock_dir = Lock_dir.get_exn context in
         match lock_dir.ocaml with
         | None -> Memo.return Package.Name.Set.empty
         | Some ocaml ->
           let+ pkg = resolve_pkg_dep context ocaml in
           Package.Name.Set.of_list_map
             (pkg :: Pkg.deps_closure pkg)
             ~f:(fun (pkg : Pkg.t) -> pkg.info.name))
  in
  Memo.exec memo
;;

let lock_dir_binaries =
  Memo.create
    "lock-directory-binaries"
    ~input:(module Context_and_packages)
    ~human_readable_description:(fun (context, packages) ->
      Some
        (Pp.textf
           "Loading the binaries of %s in the lock directory for %S"
           (describe_packages packages)
           (Context_name.to_string context)))
    (fun (context, packages) ->
       (* A lookup never builds an opaque package to see what it installs:
          only those the directory declares, and the compiler. *)
       let* compiler = compiler_packages context in
       let declared =
         match (packages : Package.Name.Selection.t) with
         | All -> compiler
         | Only packages -> Package.Name.Set.union packages compiler
       in
       let* packages = project_deps ~packages:(Only declared) context in
       let* _, opaque = Pkg.classify packages >>| Pkg.partition in
       let+ { binaries; dep_info = _ } =
         Action_expander.Artifacts_and_deps.of_closure opaque
       in
       binaries)
;;

let which ~packages context program =
  let+ binaries = Memo.exec lock_dir_binaries (context, packages) in
  Filename.Map.find binaries program
;;

(* For each locked package whose dependency closure reaches the workspace, the
   workspace packages it reaches. Building such a package while generating the
   rules of one of those packages would re-enter them. *)
let workspace_dependencies =
  let memo =
    Memo.create
      "locked-packages-workspace-dependencies"
      ~input:(module Context_name)
      (fun context ->
         let+ lock_dir = Lock_dir.get_exn context
         and+ platform = Lock_dir.Sys_vars.solver_env
         and+ { Dune_load_workspace.packages = workspace; _ } =
           Dune_load_workspace.load ()
         in
         let depends =
           Dune_pkg.Lock_dir.packages_on_platform lock_dir ~platform
           |> Package.Name.Map.map ~f:(fun (pkg : Lock_dir.Pkg.t) ->
             Dune_pkg.Lock_dir.Conditional_choice.choose_for_platform
               pkg.depends
               ~platform
             |> Option.value ~default:[]
             |> List.filter_map ~f:(fun (dep : Dune_pkg.Lock_dir.Dependency.t) ->
               Option.some_if
                 (not (Package.Name.equal dep.name Dune_pkg.Dune_dep.name))
                 dep.name))
         in
         let step reached =
           Package.Name.Map.filter_map depends ~f:(fun depends ->
             let workspace_deps =
               List.fold_left depends ~init:Package.Name.Set.empty ~f:(fun acc dep ->
                 if Package.Name.Map.mem workspace dep
                 then Package.Name.Set.add acc dep
                 else (
                   match Package.Name.Map.find reached dep with
                   | None -> acc
                   | Some deps -> Package.Name.Set.union acc deps))
             in
             Option.some_if
               (not (Package.Name.Set.is_empty workspace_deps))
               workspace_deps)
         in
         let rec loop reached =
           let next = step reached in
           if Package.Name.Map.equal ~equal:Package.Name.Set.equal next reached
           then reached
           else loop next
         in
         loop Package.Name.Map.empty)
  in
  fun context ->
    let* active = Lock_dir.lock_dir_active context in
    if active then Memo.exec memo context else Memo.return Package.Name.Map.empty
;;

let ocamlpath universe =
  let+ all_project_deps = all_deps universe in
  let env = Pkg.build_env_of_deps all_project_deps in
  Env.Map.find env Dune_findlib.Config.ocamlpath_var
  |> Option.value ~default:[]
  |> List.map ~f:(function
    | Value.Dir p | Path p -> p
    | String s -> Path.of_filename_relative_to_initial_cwd s)
;;

let project_ocamlpath context = ocamlpath (Dependencies context)
let dev_tool_ocamlpath dev_tool = ocamlpath (Dev_tool dev_tool)
let lock_dir_active = Lock_dir.lock_dir_active
let lock_dir_path = Lock_dir.get_path

let dev_tool_env tool =
  let package_name = Dune_pkg.Dev_tool.package_name tool in
  Memo.push_stack_frame ~human_readable_description:(fun () ->
    Pp.textf
      "lock directory environment for dev tools %S"
      (Package.Name.to_string package_name))
  @@ fun () ->
  let* db, pkg_digest = DB.of_dev_tool tool in
  let* pkg = Resolve.resolve db Loc.none pkg_digest (Dev_tool tool) in
  Pkg.exported_env pkg
;;

let exported_env context =
  Memo.push_stack_frame ~human_readable_description:(fun () ->
    Pp.textf "lock directory environment for context %S" (Context_name.to_string context))
  @@ fun () ->
  let+ all_project_deps = all_project_deps context in
  Pkg.build_env_of_deps all_project_deps |> Value_list_env.to_env
;;

let lock_dir_package_env =
  Memo.create
    "lock-directory-package-env"
    ~input:(module Context_and_packages)
    ~human_readable_description:(fun (context, packages) ->
      Some
        (Pp.textf
           "lock directory environment of %s for context %S"
           (describe_packages packages)
           (Context_name.to_string context)))
    (fun (context, packages) ->
       lock_dir_active context
       >>= function
       | false -> Memo.return Env.empty
       | true ->
         let+ deps = project_deps ~packages context in
         Pkg.build_env_of_deps deps |> Value_list_env.to_env)
;;

let env_for_packages ~(packages : Package.Name.Selection.t) context =
  Memo.exec lock_dir_package_env (context, packages)
;;

let bin_paths_for_packages ~packages context =
  let+ env = env_for_packages ~packages context in
  Env_path.path env
;;

let find_package ctx pkg =
  lock_dir_active ctx
  >>= function
  | false -> Memo.return None
  | true ->
    let+ pkg = resolve_pkg_dep ctx (Loc.none, pkg) in
    let dependencies =
      Pkg.deps_closure pkg
      |> Package.Name.Set.of_list_map ~f:(fun (pkg : Pkg.t) -> pkg.info.name)
    in
    Some
      ( dependencies
      , let open Action_builder.O in
        let* () = Pkg.package_deps pkg in
        Pkg.dep pkg )
;;

let package_prefixes ctx =
  lock_dir_active ctx
  >>= function
  | false -> Memo.return []
  | true ->
    all_project_deps ctx
    >>| List.map ~f:(fun { Pkg.info = { name; _ }; paths = { Paths.prefix; _ }; _ } ->
      prefix, name)
;;

let resolve_installed_file ~loc ~context_name ~pkg_name ~section ~file =
  let open Action_builder.O in
  let* pkg = Action_builder.of_memo (resolve_pkg_dep context_name (loc, pkg_name)) in
  let* { Dependency.paths; files; _ } = Pkg.dependency pkg in
  let section_dir =
    let install_paths = Lazy.force paths.install_paths in
    Install.Paths.get install_paths section
  in
  let path = Path.append_local section_dir file in
  let installed = Section.Map.find files section |> Option.value ~default:[] in
  match List.exists installed ~f:(Path.equal path) with
  | true ->
    let+ () = Action_builder.path path in
    path
  | false ->
    let file_str = Path.Local.to_string file in
    let candidates =
      List.filter_map installed ~f:(Path.drop_prefix ~prefix:section_dir)
      |> List.map ~f:Path.Local.to_string
    in
    User_error.raise
      ~loc
      ~hints:(User_message.did_you_mean file_str ~candidates)
      [ Pp.textf
          "File %s not found in section %s of package %s"
          file_str
          (Section.to_string section)
          (Package.Name.to_string pkg_name)
      ]
;;

let all_filtered_depexts context =
  let* all_project_deps = all_project_deps context in
  Memo.List.map all_project_deps ~f:(fun (pkg : Pkg.t) ->
    let expander = Action_expander.expander_with_env context pkg ~env:Env.Map.empty in
    Action_expander.Expander.filtered_depexts expander)
  >>| List.concat
  >>| List.sort_uniq ~compare:String.compare
;;

let pkg_digest_of_project_dependency ctx package_name =
  let+ db = DB.of_ctx ctx ~allow_sharing:false in
  Pkg_digest.Map.keys db.pkg_digest_table
  |> List.find ~f:(fun (pkg_digest : Pkg_digest.t) ->
    Package.Name.equal pkg_digest.name package_name)
;;
