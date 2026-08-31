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
