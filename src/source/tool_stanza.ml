open Import

(** Tool configuration from (tool ...) stanza in dune-workspace.

    The package field uses the same dependency syntax as (depends ...):
    - Just package name: ocamlformat
    - With version constraint: (ocamlformat (= 0.26.2))

    Syntax examples:
    {v
    ;; Simple - just package name
    (tool (package ocamlformat))

    ;; With version constraint
    (tool (package (ocamlformat (= 0.26.2))))

    ;; With additional options
    (tool
      (package (ocamlformat (= 0.26.2)))
      (executable ocamlformat-rpc)
      (compiler_compatible))
    v}
*)

type t =
  { package : Package.Name.t
  ; version : Package_constraint.t option
  ; executable : string option
  ; compiler_compatible : bool
  ; repositories : string list option  (** Repository names to use for this tool *)
  ; loc : Loc.t
  }

let to_dyn { package; version; executable; compiler_compatible; repositories; loc } =
  Dyn.record
    [ "package", Package.Name.to_dyn package
    ; "version", Dyn.option Package_constraint.to_dyn version
    ; "executable", Dyn.option Dyn.string executable
    ; "compiler_compatible", Dyn.bool compiler_compatible
    ; "repositories", Dyn.option (Dyn.list Dyn.string) repositories
    ; "loc", Loc.to_dyn loc
    ]
;;

let equal a b =
  Package.Name.equal a.package b.package
  && Option.equal Package_constraint.equal a.version b.version
  && Option.equal String.equal a.executable b.executable
  && Bool.equal a.compiler_compatible b.compiler_compatible
  && Option.equal (List.equal String.equal) a.repositories b.repositories
  && Loc.equal a.loc b.loc
;;

let hash { package; version; executable; compiler_compatible; repositories; loc } =
  Poly.hash (package, version, executable, compiler_compatible, repositories, loc)
;;

let package_name t = t.package
let exe_name t = Option.value t.executable ~default:(Package.Name.to_string t.package)
let needs_matching_compiler t = t.compiler_compatible
let version_constraint t = t.version
let repositories t = t.repositories

let decode =
  let open Dune_lang.Decoder in
  fields
    (let+ loc = loc
     and+ dep = field "package" Package_dependency.decode
     and+ executable = field_o "executable" string
     and+ compiler_compatible = field_b "compiler_compatible"
     and+ repositories = field_o "repositories" (repeat string) in
     { package = dep.name
     ; version = dep.constraint_
     ; executable
     ; compiler_compatible
     ; repositories
     ; loc
     })
;;

let encode { package; version; executable; compiler_compatible; repositories; loc = _ } =
  let open Dune_lang.Encoder in
  let dep_encoding =
    Package_dependency.encode { Package_dependency.name = package; constraint_ = version }
  in
  (* Return as a list starting with the dependency encoding *)
  dep_encoding
  :: record_fields
       [ field_o "executable" string executable
       ; field_b "compiler_compatible" compiler_compatible
       ; field_l "repositories" string (Option.value repositories ~default:[])
       ]
;;
