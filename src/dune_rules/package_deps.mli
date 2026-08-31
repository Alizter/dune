(** Concrete capabilities materialized for a set of package dependencies. *)

open Import

module Variable : sig
  type value = OpamVariable.variable_contents =
    | B of bool
    | S of string
    | L of string list

  type t = Package_variable_name.t * value

  val repr : t Repr.t
  val dune_value : value -> Value.t list
  val of_values : dir:Path.t -> Value.t list -> value
end

module Paths : sig
  type 'a t =
    { source_dir : 'a
    ; target_dir : 'a
    ; extra_sources : 'a
    ; name : Package.Name.t
    ; install_roots : 'a Install.Roots.t Lazy.t
    ; install_paths : 'a Install.Paths.t Lazy.t
    ; prefix : 'a
    }

  val map_path : 'a t -> f:('a -> 'b) -> 'b t
  val of_root : Package.Name.t -> root:'a -> relative:('a -> string -> 'a) -> 'a t
  val with_install_root : Path.t t -> Path.t -> Path.t t
  val of_local_package : Package.t -> install_root:Path.t -> Path.t t
  val extra_source : Path.t t -> Path.Local.t -> Path.t
  val extra_source_build : Path.Build.t t -> Path.Local.t -> Path.Build.t
  val install_cookie' : Path.Build.t -> Path.Build.t
  val install_cookie : Path.t t -> Path.t
  val install_file : Path.Build.t t -> Path.Build.t
  val config_file : Path.Build.t t -> Path.Build.t
  val install_paths : 'a t -> 'a Install.Paths.t
  val install_roots : 'a t -> 'a Install.Roots.t
  val target_dir : 'a t -> 'a
end

module Install_cookie : sig
  module Gen : sig
    type 'files t =
      { files : 'files
      ; variables : Variable.t list
      }
  end

  type t = Path.t list Section.Map.t Gen.t

  val load_exn : Path.t -> t
  val dump : Path.t -> t -> unit
end

type package_variables = Variable.value Package_variable_name.Map.t
type concrete_paths = Path.t Paths.t

val variables : Package.t -> package_variables

type t =
  { env : Env.t
  ; binaries : Path.t Filename.Map.t
  ; packages : (package_variables * concrete_paths) Package.Name.Map.t
  }

val empty : t
