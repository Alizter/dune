open Import

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

module Paths = struct
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

  let of_root name ~root ~relative =
    let source_dir = relative root "source" in
    let target_dir = relative root "target" in
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

  let with_install_root t target_dir =
    let install_roots = lazy (install_roots ~target_dir ~relative:Path.relative) in
    let install_paths =
      lazy (install_paths (Lazy.force install_roots) t.name ~relative:Path.relative)
    in
    { t with target_dir; install_roots; install_paths; prefix = target_dir }
  ;;

  let of_local_package package ~install_root =
    let name = Package.name package in
    let source_dir = Package.dir package |> Source_path.to_path in
    let install_roots =
      lazy (install_roots ~target_dir:install_root ~relative:Path.relative)
    in
    let install_paths =
      lazy (install_paths (Lazy.force install_roots) name ~relative:Path.relative)
    in
    { source_dir
    ; target_dir = install_root
    ; extra_sources = source_dir
    ; name
    ; install_roots
    ; install_paths
    ; prefix = install_root
    }
  ;;

  let extra_source t extra_source = Path.append_local t.extra_sources extra_source

  let extra_source_build t extra_source =
    Path.Build.append_local t.extra_sources extra_source
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
  let target_dir t = t.target_dir
end

module Install_cookie = struct
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

  let load_exn file =
    match Persistent.load file with
    | Some cookie -> { cookie with files = Section.Map.of_list_exn cookie.files }
    | None -> User_error.raise ~loc:(Loc.in_file file) [ Pp.text "unable to load" ]
  ;;

  let dump path (t : t) =
    Persistent.dump path { t with files = Section.Map.to_list t.files }
  ;;
end

module Value_list_env = struct
  type t = Value.t list Env.Map.t

  let of_env env : t =
    Env.to_map env
    |> Env.Map.map ~f:(fun value ->
      Bin.parse value |> List.map ~f:(fun value -> Value.String value))
  ;;

  let global : t Lazy.t = lazy (of_env (Global.env ()))

  let string_of_env_values values =
    List.map values ~f:(function
      | Value.String value -> value
      | Dir path | Path path -> Path.to_absolute_filename path)
    |> Bin.encode_strings
  ;;

  let to_env (t : t) = Env.Map.map t ~f:string_of_env_values |> Env.of_map
  let get_path t = Env.Map.find t Env_path.var

  let extend_concat_path a b =
    let extended = Env.Map.superpose b a in
    let concatenated_path =
      match get_path a, get_path b with
      | None, None -> None
      | Some path, None | None, Some path -> Some path
      | Some a, Some b -> Some (b @ a)
    in
    match concatenated_path with
    | None -> extended
    | Some path -> Env.Map.set extended Env_path.var path
  ;;

  let add_path (t : t) var path : t =
    Env.Map.update t var ~f:(fun paths ->
      let paths = Option.value paths ~default:[] in
      Some (Value.Dir path :: paths))
  ;;
end

module Env_update = struct
  include Dune_lang.Action.Env_update

  let update kind ~new_v ~old_v ~f =
    if new_v = ""
    then old_v
    else (
      match kind with
      | `Colon ->
        let old_v =
          match old_v with
          | None | Some [] -> [ Value.String "" ]
          | Some value -> value
        in
        Some (f ~old_v ~new_v)
      | `Plus ->
        (match old_v with
         | None | Some [] -> Some [ Value.String new_v ]
         | Some old_v -> Some (f ~old_v ~new_v)))
  ;;

  let append = update ~f:(fun ~old_v ~new_v -> old_v @ [ Value.String new_v ])
  let prepend = update ~f:(fun ~old_v ~new_v -> Value.String new_v :: old_v)

  let set env { op; var; value = new_v } =
    Env.Map.update env var ~f:(fun old_v ->
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
      | EqPlusEq -> Code_error.raise "Unsupported package environment update" [])
  ;;
end

type package_variables = Variable.value Package_variable_name.Map.t
type concrete_paths = Path.t Paths.t

let variables package =
  let name = Package.name package in
  let version, dev =
    match Package.version package with
    | Some version -> version, false
    | None -> Dune_pkg.Lock_dir.Pkg_info.default_version, true
  in
  Package_variable_name.Map.of_list_exn
    [ Package_variable_name.name, Variable.S (Package.Name.to_string name)
    ; Package_variable_name.version, S (Package_version.to_string version)
    ; Package_variable_name.dev, B dev
    ]
;;

type t =
  { env : Env.t
  ; binaries : Path.t Filename.Map.t
  ; packages : (package_variables * concrete_paths) Package.Name.Map.t
  }

let empty =
  { env = Env.empty; binaries = Filename.Map.empty; packages = Package.Name.Map.empty }
;;

let add_package t ~paths ~variables ~files ~exported_env =
  let env =
    let roots = Paths.install_roots paths in
    let env =
      let init =
        Value_list_env.add_path (Value_list_env.of_env t.env) Env_path.var roots.bin
      in
      Install.Roots.to_env_without_path roots ~relative:Path.relative
      |> List.fold_left ~init ~f:(fun env (var, path) ->
        Value_list_env.add_path env var path)
    in
    List.fold_left exported_env ~init:env ~f:Env_update.set |> Value_list_env.to_env
  in
  let binaries =
    Section.Map.Multi.find files Bin
    |> List.fold_left ~init:t.binaries ~f:(fun binaries path ->
      let name =
        Path.basename path
        |> Filename.to_string
        |> Bin.strip_exe
        |> Filename.of_string_exn
      in
      Filename.Map.set binaries name path)
  in
  let packages = Package.Name.Map.set t.packages paths.name (variables, paths) in
  { env; binaries; packages }
;;
