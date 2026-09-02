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

module Value_list_env : sig
  type t = Value.t list Env.Map.t

  val global : t Lazy.t
  val of_env : Env.t -> t
  val string_of_env_values : Value.t list -> string
  val to_env : t -> Env.t
  val extend_concat_path : t -> t -> t
  val add_path : t -> Env.Var.t -> Path.t -> t
end

module Env_update : sig
  include module type of Dune_lang.Action.Env_update

  val set : Value_list_env.t -> string t -> Value_list_env.t
end

type package_variables = Variable.value Package_variable_name.Map.t
type concrete_paths = Path.t Paths.t

val variables : Package.t -> package_variables

type t =
  { value_env : Value_list_env.t
  ; binaries : Path.t Filename.Map.t
  ; packages : (package_variables * concrete_paths) Package.Name.Map.t
  }

val empty : t
val env : t -> Env.t

val add_package
  :  t
  -> paths:concrete_paths
  -> variables:package_variables
  -> files:Path.t list Section.Map.t
  -> exported_env:string Env_update.t list
  -> t
