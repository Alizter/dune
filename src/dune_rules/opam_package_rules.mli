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

module Package_universe : sig
  type t =
    | Dependencies of Context_name.t
    | Dev_tool of Dune_pkg.Dev_tool.t

  val equal : t -> t -> bool
  val hash : t -> int
  val context_name : t -> Context_name.t
  val lock_dir_path : t -> Path.t option Memo.t
  val lock_dir : t -> Dune_pkg.Lock_dir.t Memo.t
end

module Pkg_digest : sig
  type t =
    { name : Package.Name.t
    ; version : Package_version.t
    ; lockfile_and_dependency_digest : Dune_digest.t
    }

  include Comparable_intf.S with type key := t

  val equal : t -> t -> bool
  val compare : t -> t -> Ordering.t
  val to_dyn : t -> Dyn.t
  val hash : t -> int
  val repr : t Repr.t
  val to_string : t -> string
  val of_string : string -> t
  val create : Dune_pkg.Lock_dir.Pkg.t -> t list -> t
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

  val make
    :  Pkg_digest.t
    -> Package_universe.t
    -> relative:(Path.Build.t -> string -> Path.Build.t)
    -> Path.Build.t t

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

module Source_input : sig
  (** Source inputs for an opaque package build. [files_dir] is overlaid on
      [root], followed by [extra_sources] in list order, inside the rule's copy
      sandbox. *)
  type t =
    { root : Path.Build.t
    ; files_dir : Path.Build.t option
    ; extra_sources : (Path.Local.t * Path.t) list
    }
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
  val string_of_env_values : Value.t list -> string
  val to_env : t -> Env.t
  val extend_concat_path : t -> t -> t
  val add_path : t -> Env.Var.t -> Path.t -> t
end

module Env_update : sig
  include module type of Dune_lang.Action.Env_update

  val set : Value_list_env.t -> string t -> Value_list_env.t
end

module Pkg : sig
  module Id : Id.S

  type t =
    { id : Id.t
    ; build_command : Dune_pkg.Lock_dir.Build_command.t option
    ; install_command : Dune_lang.Action.t option
    ; depends : t list
    ; depends_on_dune : bool
    ; depexts : Dune_pkg.Lock_dir.Depexts.t list
    ; info : Dune_pkg.Lock_dir.Pkg_info.t
    ; paths : Path.t Paths.t
    ; write_paths : Path.Build.t Paths.t
    ; files_dir : Path.Build.t
    ; pkg_digest : Pkg_digest.t
    ; unexpanded_exported_env : String_with_vars.t Env_update.t list
    ; mutable exported_env : string Env_update.t list
    }

  val top_closure : t list -> t list
  val deps_closure : t -> t list
  val dep : t -> Dep.t
  val package_deps_of : t list -> Dep.Set.t
  val install_roots : t -> Path.t Install.Roots.t
  val build_env_of_deps : t list -> Value_list_env.t
  val exported_value_env_with_deps : t -> t list -> Value_list_env.t
  val exported_value_env : t -> Value_list_env.t
  val exported_env_with_deps : t -> t list -> Env.t
  val exported_env : t -> Env.t
end

module Pkg_installed : sig
  type t = { cookie : Install_cookie.t Action_builder.t }

  val of_paths : Path.t Paths.t -> t
end

module Dependency_view : sig
  type t =
    { all : Pkg.t list
    ; legacy : Pkg.t list
    ; mounted : Pkg.t list
    ; mounted_names : Package.Name.Set.t
    }

  val of_list
    :  Context_name.t
    -> Pkg.t list
    -> is_mounted:(Pkg.t -> bool Memo.t)
    -> t Memo.t

  val make : Context_name.t -> Pkg.t -> is_mounted:(Pkg.t -> bool Memo.t) -> t Memo.t
end

module Action_expander : sig
  module Expander : sig
    type t

    val filtered_depexts : t -> string list Memo.t
  end

  module Artifacts_and_deps : sig
    type artifacts_and_deps =
      { binaries : Path.t Filename.Map.t
      ; dep_info :
          (OpamVariable.variable_contents Package_variable_name.Map.t * Path.t Paths.t)
            Package.Name.Map.t
      }

    val of_dependency_view
      :  Context_name.t
      -> Dependency_view.t
      -> artifacts_and_deps Memo.t
  end

  val expander : Context_name.t -> Pkg.t -> Dependency_view.t -> Expander.t

  val exported_env
    :  Expander.t
    -> String_with_vars.t Env_update.t
    -> string Env_update.t Memo.t

  val refresh_exported_env : Context_name.t -> Dependency_view.t -> unit Memo.t
end

val source_rules : Pkg.t -> (Dep.Set.t * unit Memo.t) Memo.t

val gen_rules
  :  Context_name.t
  -> Pkg.t
  -> source:Source_input.t
  -> source_deps:Dep.Set.t
  -> dependencies:Dependency_view.t
  -> unit Memo.t
