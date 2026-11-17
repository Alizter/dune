(** rules for packages built by dune *)

open Import

(** Selected lock packages use the context's [.pkg/<name>] subtree. Source
    snapshots are prepared independently in [_fetch]; opaque recipes install
    under [_install] within the package mount. Dev tools and their unshared
    dependencies retain their private package directories. *)

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

  val of_root
    :  Package.Name.t
    -> root:'a
    -> source_dir:string
    -> install_dir:string
    -> relative:('a -> string -> 'a)
    -> 'a t

  val map_path : 'a t -> f:('a -> 'b) -> 'b t
  val install_roots : 'a t -> 'a Install.Roots.t
end

val candidate_paths : Pkg_sources.Candidate.t -> Path.Build.t Paths.t

module Dependency : sig
  type t

  val paths : t -> Path.t Paths.t

  (** The package's dependency in a shared install layout at [prefix]. *)
  val native
    :  Path.t Paths.t
    -> prefix:Path.t
    -> variables:OpamVariable.variable_contents Package_variable_name.Map.t
    -> exported_env:String_with_vars.t Dune_lang.Action.Env_update.t list
    -> t

  val install_entries : t -> Path.t Install.Entry.Expanded.t list
end

module Layout : sig
  type t

  (** Materialize selected providers and register dependencies on installed
      files, without applying exports. Preserve the supplied order for applying
      exports. *)
  val materialize : Context_name.t -> Dependency.t list -> t Action_builder.t
end

(** Prepend the layout's standard paths to [base], then apply package exports
    in order and record their environment dependencies. *)
val layout_env : Layout.t -> path:Path.t list -> base:Env.t -> Env.t Action_builder.t

val setup_rules
  :  components:string list
  -> dir:Path.Build.t
  -> Context_name.t
  -> Build_config.Gen_rules.t Memo.t

(** Rules for [_build/_private/<context>/.dune-source/<package>]: the fetched
    source of a package with its lock directory files, extra sources and
    leading patches applied. Only packages that need this have rules. *)
val gen_prepared_source_rules
  :  Context_name.t
  -> dir:Path.Build.t
  -> string list
  -> Build_config.Gen_rules.t Memo.t

val gen_mounted_rule
  :  Context_name.t
  -> Pkg_sources.Candidate.t
  -> dependencies:(Package.Name.Set.t * Layout.t) Action_builder.t
  -> unit Memo.t

(** For each locked package whose dependency closure reaches the workspace, the
    workspace packages it reaches. *)
val workspace_dependencies
  :  Context_name.t
  -> Package.Name.Set.t Package.Name.Map.t Memo.t

val lock_dir_path : Context_name.t -> Path.t option Memo.t
val lock_dir_active : Context_name.t -> bool Memo.t
val ocaml_toolchain : Context_name.t -> Ocaml_toolchain.t Action_builder.t option Memo.t

(** [packages] with the package installing the compiler and its dependencies.
    Their binaries are visible from every directory, whatever it declares. *)
val declared_packages
  :  Context_name.t
  -> Package.Name.Selection.t
  -> Package.Name.Set.t Memo.t

(** [which ~packages context program] looks [program] up among the binaries
    installed by opaque [packages] in the lock directory. Native declarations
    are resolved by [Artifacts] before this fallback. The caller supplies the
    packages visible to the requester, including any explicit dependencies.
    The package installing the compiler and its dependencies are always
    searched. *)
val which
  :  packages:Package.Name.Selection.t
  -> Context_name.t
  -> Filename.t
  -> Path.t option Memo.t

(** [env_for_packages ~packages context] is an env holding environment
    variables constructed from the opaque [packages] in the lock directory.
    Native packages use the consumer's shared install layout. Only the named
    packages are included, not their dependencies. [All] means all opaque
    packages. Empty when the context has no lock directory. *)
val env_for_packages : packages:Package.Name.Selection.t -> Context_name.t -> Env.t Memo.t

(** [bin_paths_for_packages ~packages context] returns a list of bin
    directories of opaque [packages] in the lock directory. [All] means all
    opaque packages. Empty when the context has no lock directory. *)
val bin_paths_for_packages
  :  packages:Package.Name.Selection.t
  -> Context_name.t
  -> Path.t list Memo.t

val exported_env : Context_name.t -> Env.t Memo.t
val project_ocamlpath : Context_name.t -> Path.t list Memo.t
val dev_tool_ocamlpath : Dune_pkg.Dev_tool.t -> Path.t list Memo.t

(** The selected lock dependency closure and the action that builds its outputs.
    Inspecting the names does not build the package. *)
val find_package
  :  Context_name.t
  -> Package.Name.t
  -> (Package.Name.Set.t * unit Action_builder.t) option Memo.t

val dependency
  :  Context_name.t
  -> Pkg_sources.Candidate.t
  -> Dependency.t Action_builder.t Memo.t

val find_opaque
  :  Context_name.t
  -> Package.Name.t
  -> (Path.Build.t * Dependency.t Action_builder.t) option Memo.t

(* CR-someday Alizter: These prefixes would be [Path.Build.t] if not for
   the "toolchain" mechanism, which installs outside the build directory. *)

(** Opaque installation prefixes and owning packages from the context's lock
    directory. Native libraries use ordinary workspace library resolution. *)
val package_prefixes : Context_name.t -> (Path.t * Package.Name.t) list Memo.t

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
