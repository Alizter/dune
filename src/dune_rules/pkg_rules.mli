(** rules for packages built by dune *)

open Import

(** The package management rules setup two rules for every package:

    - A rule for fetching the source to produce .pkg/$package/source

    - A rule to build the package and produce the artifacts in
      .pkg/$package/target.

    It setups an alias rules to trigger the fetch and build of the
    package universe. *)

val setup_rules
  :  components:string list
  -> dir:Path.Build.t
  -> Context_name.t
  -> Build_config.Gen_rules.t Memo.t

val lock_dir_path : Context_name.t -> Path.t option Memo.t
val lock_dir_active : Context_name.t -> bool Memo.t
val gen_opam_rules : Context_name.t -> dir:Path.Build.t -> Package.Name.t -> unit Memo.t

val setup_mounted_opam_package_rules
  :  Context_name.t
  -> Pkg_sources.Mounted.t
  -> dir:Path.Build.t
  -> components:string list
  -> Build_config.Gen_rules.t Memo.t

val ocaml_toolchain : Context_name.t -> Ocaml_toolchain.t Action_builder.t option Memo.t

(** [which ~packages context program] looks [program] up among the binaries
    installed by the dependency closure of [packages] in the lock directory.
    [None] means the whole lock directory. *)
val which
  :  packages:Package.Name.Set.t option
  -> Context_name.t
  -> Filename.t
  -> Path.t option Memo.t

val binaries_for_package
  :  Context_name.t
  -> Package.Name.t
  -> Path.t Filename.Map.t Memo.Lazy.t

val package_binaries
  :  packages:Package.Name.Set.t option
  -> Context_name.t
  -> Path.t Filename.Map.t Memo.t

(** [bin_path_env ~packages context] is an env holding only a PATH made of the
    bin directories of the dependency closure of [packages] in the lock
    directory. [None] means the whole lock directory. Empty when the context
    has no lock directory. *)
val bin_path_env : packages:Package.Name.Set.t option -> Context_name.t -> Env.t Memo.t

val exported_env : Context_name.t -> Env.t Memo.t
val project_ocamlpath : Context_name.t -> Path.t list Memo.t

module Legacy_libraries : sig
  type t

  val for_package : Context_name.t -> Package.Name.t -> t Memo.t
  val find : t -> Package.Name.t -> Path.t list option Memo.t
  val find_provider : t -> Package.Name.t -> Path.t list option Memo.t
  val packages : t -> Package.Name.t list
end

val dev_tool_ocamlpath : Dune_pkg.Dev_tool.t -> Path.t list Memo.t
val find_package : Context_name.t -> Package.Name.t -> unit Action_builder.t option Memo.t

val resolve_installed_file
  :  loc:Loc.t
  -> context_name:Context_name.t
  -> pkg_name:Package.Name.t
  -> section:Section.t
  -> file:Path.Local.t
  -> Path.t Action_builder.t

val dev_tool_env : Dune_pkg.Dev_tool.t -> Env.t Memo.t
val all_filtered_depexts : Context_name.t -> string list Memo.t

val setup_pkg_install_alias
  :  dir:Path.Build.t
  -> Context_name.t
  -> Build_config.Gen_rules.t

module Pkg_digest : sig
  type t

  val to_string : t -> string
end

val pkg_digest_of_project_dependency
  :  Context_name.t
  -> Package.Name.t
  -> Pkg_digest.t option Memo.t
