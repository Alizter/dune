(** Workspaces definitions *)

open Import
module Ordered_set_lang := Dune_lang.Ordered_set_lang
module Dune_env := Dune_lang.Dune_env
module Pin_stanza := Dune_lang.Pin_stanza
module Lib_name := Dune_lang.Lib_name

module Lock_dir : sig
  type t =
    { loc : Loc.t
    ; path : Path.Source.t
    ; version_preference : Dune_pkg.Version_preference.t option
    ; solver_env : Dune_pkg.Solver_env.t option
    ; unset_solver_vars : Dune_lang.Package_variable_name.Set.t option
    ; repositories : (Loc.t * Dune_pkg.Pkg_workspace.Repository.Name.t) list
    ; constraints : Dune_lang.Package_dependency.t list
    ; pins : (Loc.t * string) list
    ; depopts : (Loc.t * Package.Name.t) list
    ; solve_for_platforms : Dune_pkg.Solver_env.t list
    }

  val equal : t -> t -> bool
  val to_dyn : t -> Dyn.t
end

module Lock_dir_selection : sig
  (** A DSL for selecting a lockdir either by literally naming it or using a
      cond expression to select a lockdir based on blangs *)
  type t

  val eval
    :  t
    -> dir:Path.Source.t
    -> f:Value.t list Memo.t String_with_vars.expander
    -> Path.Source.t Memo.t
end

(** Per-internal-build-context source-tree backing. Each entry returned
    by [build_contexts] is paired with one of these, telling callers
    which source tree the internal context reads from. *)
module Mount_path : sig
  (** A mount's underlying path. External paths come from
      [(mount ...)] stanzas in [dune-workspace]; build paths come from
      synthesised pkg-mount contexts whose source bytes live under
      [_build/]. *)
  type t =
    | External of Path.External.t
    | Build of Path.Build.t

  val equal : t -> t -> bool
  val to_dyn : t -> Dyn.t
end

module Build_context_source : sig
  type t =
    | Workspace
    | Mount of Mount_path.t
    | Vcs_rev of Dune_vcs.Vcs_tree.t

  val equal : t -> t -> bool
  val to_dyn : t -> Dyn.t
end

module Context : sig
  module Target : sig
    type named =
      { name : Context_name.t
      ; target_exec : (string * string list) option
      }

    type t =
      | Native
      | Named of named

    val equal : t -> t -> bool
  end

  module Merlin : sig
    type t =
      | Selected
      | Rules_only
      | Not_selected

    val equal : t -> t -> bool
    val to_dyn : t -> Dyn.t
  end

  module Cms_cmt_dependency : sig
    type t =
      | No_dependency
      | Depends_on_cms
      | Depends_on_cmt

    val equal : t -> t -> bool
    val to_dyn : t -> Dyn.t
  end

  module Mount : sig
    (** A user-declared source-tree mount attached to a context. At build time,
        the mount is wired to an internal build context whose [Source_tree.t]
        is rooted at [path]. *)
    type t =
      { loc : Loc.t
      ; path : Mount_path.t
      }

    val equal : t -> t -> bool
    val to_dyn : t -> Dyn.t

    (** Internal-context-name suffix derived from the mount's path. Currently
        the path's basename; raises a [User_error] if the basename is not a
        valid [Context_name.t]. *)
    val internal_name : t -> Context_name.t
  end

  module Common : sig
    type t =
      { loc : Loc.t
      ; profile : Profile.t
      ; targets : Target.t list
      ; env : Dune_env.t option
      ; toolchain : Context_name.t option
      ; name : Context_name.t
      ; host_context : Context_name.t option
      ; paths : (string * Ordered_set_lang.t) list
      ; fdo_target_exe : Path.t option
        (** By default Dune builds and installs dynamically linked foreign
          archives (usually named [dll*.so]). It is possible to disable
          this by setting [disable_dynamically_linked_foreign_archives] to
          [true] in the workspace file, in which case bytecode executables
          will be built with all foreign archives statically linked into
          the runtime system. *)
      ; dynamically_linked_foreign_archives : bool
      ; instrument_with : Lib_name.t list
      ; merlin : Merlin.t
      ; cms_cmt_dependency : Cms_cmt_dependency.t
      ; mounts : Mount.t list
      ; vcs_tree : Dune_vcs.Vcs_tree.t option
      }
  end

  module Opam : sig
    type t =
      { base : Common.t
        (** Either a switch name or a path to a local switch. This argument
          is left opaque as we leave to opam to interpret it. *)
      ; switch : Opam_switch.t
      }
  end

  module Default : sig
    type t =
      { base : Common.t
      ; lock_dir : Lock_dir_selection.t option
      }
  end

  type t =
    | Default of Default.t
    | Opam of Opam.t

  val loc : t -> Loc.t
  val name : t -> Context_name.t
  val env : t -> Dune_env.t option
  val host_context : t -> Context_name.t option
  val to_dyn : t -> Dyn.t
  val base : t -> Common.t
end

(** Representation of a workspace. The list of context is topologically sorted,
    i.e. a context always comes before the contexts where it is used as host
    context.

    The various field aggregate all of, by order of precedence:

    - the command line arguments
    - the contents of the workspace file
    - the contents of the user configuration file
    - the default values *)
type t = private
  { merlin_context : Context_name.t option
  ; contexts : Context.t list
  ; env : Dune_env.t option
  ; config : Dune_config.t
  ; repos : Dune_pkg.Pkg_workspace.Repository.t list
  ; lock_dirs : Lock_dir.t list
  ; dir : Path.Source.t
  ; pins : Pin_stanza.Workspace.t
  ; vcs_revs : (Context_name.t * Dune_vcs.Vcs_tree.t) list
  }

val equal : t -> t -> bool
val to_dyn : t -> Dyn.t
val hash : t -> int
val find_lock_dir : t -> Path.t -> Lock_dir.t option
val add_repo : t -> Dune_pkg.Pkg_workspace.Repository.t -> t
val default_repositories : Dune_pkg.Pkg_workspace.Repository.t list

module Clflags : sig
  type t =
    { x : Context_name.t option
    ; profile : Profile.t option
    ; instrument_with : Lib_name.t list option
    ; workspace_file : Path.Outside_build_dir.t option
    ; config_from_command_line : Dune_config.Partial.t
    ; config_from_config_file : Dune_config.Partial.t
    }

  val equal : t -> t -> bool

  (** This must be called exactly once *)
  val set : t -> unit
end

(** Default name of workspace files *)
val filename : Filename.t

val workspace : unit -> t Memo.t

(** Synthesise a workspace consisting solely of vcs-rev contexts —
    one user-facing [Build_context.t] per [(name, vcs_tree)] entry,
    named exactly as given. Used to back [dune build -r <rev>] without
    requiring a [dune-workspace] file. The on-disk [dune-workspace]
    is not consulted. *)
val synthesise_for_revs : (Context_name.t * Dune_vcs.Vcs_tree.t) list -> t

(** One-shot hook used by [workspace ()]: when set, the resolver is
    invoked once inside the Memo computation that loads the workspace,
    and the resulting list is used to synthesise it (bypassing
    [dune-workspace] parsing entirely). Called by the CLI layer when
    [-r] flags are present; the resolver does the actual rev lookup
    (e.g., [Vcs_tree.resolve_set]). *)
val set_synthesised_for_revs
  :  (unit -> (Context_name.t * Dune_vcs.Vcs_tree.t) list Fiber.t)
  -> unit

(** Hook for pkg-mount synthesis: for each context, return additional
    [Mount.t] entries (typically with [Build] paths) to append to its
    [Common.t.mounts]. Called by [Main.init] to wire [(dune)] pkgs
    into the existing mount machinery. *)
val set_pkg_mounts_synthesiser
  :  (Context_name.t -> Context.Mount.t list Memo.t)
  -> unit

(** Same as [workspace ()] except that if there are errors related to fields
    other than the ones of [config], they are not reported. *)
val workspace_config : unit -> Dune_config.t Memo.t

(** Update the execution parameters according to what is written in the
    [dune-workspace] file. *)
val update_execution_parameters : t -> Execution_parameters.t -> Execution_parameters.t

(** All the internal build contexts defined in the workspace.
    Each entry is paired with the source-tree backing it should read
    from. *)
val build_contexts : t -> (Build_context.t * Build_context_source.t) list
