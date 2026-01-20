open Import
open Memo.O

(** Compiler detection for tools.

    This module detects how the project gets its compiler and generates
    appropriate constraints for tool solving. The key insight is that
    tools should use the same compiler as the project:
    - If from pkg management, match that pkg's compiler
    - If from system, use system-ocaml
*)

type compiler_source =
  | From_pkg of
      { name : Package.Name.t
      ; version : Package_version.t
      }
  | From_system of { version : string }
  | From_opam_switch of { prefix : string }
  | Unknown

let to_dyn = function
  | From_pkg { name; version } ->
    Dyn.variant
      "From_pkg"
      [ Dyn.record
          [ "name", Package.Name.to_dyn name
          ; "version", Package_version.to_dyn version
          ]
      ]
  | From_system { version } ->
    Dyn.variant "From_system" [ Dyn.record [ "version", Dyn.string version ] ]
  | From_opam_switch { prefix } ->
    Dyn.variant "From_opam_switch" [ Dyn.record [ "prefix", Dyn.string prefix ] ]
  | Unknown -> Dyn.variant "Unknown" []
;;

(** Try to get compiler info from the project's lock directory *)
let compiler_from_lock_dir () =
  let context = Context_name.default in
  let* result = Lock_dir.get context in
  match result with
  | Error _ -> Memo.return None
  | Ok lock_dir ->
    let* platform = Lock_dir.Sys_vars.solver_env in
    let pkgs =
      Dune_pkg.Lock_dir.Packages.pkgs_on_platform_by_name lock_dir.packages ~platform
    in
    (match lock_dir.ocaml with
     | None -> Memo.return None
     | Some (_loc, pkg_name) ->
       (match Package.Name.Map.find pkgs pkg_name with
        | None -> Memo.return None
        | Some pkg ->
          Memo.return (Some (From_pkg { name = pkg.info.name; version = pkg.info.version }))))
;;

(** Detect compiler source for the default context.
    Priority: lock dir > opam switch > system *)
let detect () =
  let* from_lock = compiler_from_lock_dir () in
  match from_lock with
  | Some source -> Memo.return source
  | None ->
    (* Check if there's an opam switch prefix in the environment *)
    let env = Global.env () in
    (match Env.get env Opam_switch.opam_switch_prefix_var_name with
     | Some prefix -> Memo.return (From_opam_switch { prefix })
     | None ->
       (* Try to detect system ocaml version via ocamlc -version *)
       let* sys_ocaml_version = Memo.Lazy.force Lock_dir.Sys_vars.poll.sys_ocaml_version in
       (match sys_ocaml_version with
        | Some version -> Memo.return (From_system { version })
        | None -> Memo.return Unknown))
;;

(** Generate package dependencies for tool solving based on compiler source.
    This ensures tools are built with a compatible compiler. *)
let constraints_for_tool compiler_source =
  match compiler_source with
  | From_pkg { name; version } ->
    let constraint_ =
      Some
        (Package_constraint.Uop
           (Eq, String_literal (Package_version.to_string version)))
    in
    [ { Package_dependency.name; constraint_ } ]
  | From_system { version } ->
    (* For system compiler, constrain to system-ocaml package with matching version *)
    let constraint_ =
      Some (Package_constraint.Uop (Eq, String_literal version))
    in
    [ { Package_dependency.name = Package.Name.of_string "ocaml"; constraint_ } ]
  | From_opam_switch _ ->
    (* For opam switch, the switch already provides the compiler, no constraints needed *)
    []
  | Unknown ->
    (* No constraints if we can't detect the compiler *)
    []
;;

(** Get compiler constraints for a tool, detecting the compiler source first *)
let get_constraints () =
  let+ source = detect () in
  constraints_for_tool source
;;
