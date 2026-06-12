(** Dune representation of the source tree *)

open Import

module Dir : sig
  type t

  val path : t -> Path.Source.t
  val filenames : t -> Filename.Array.Set.t

  type sub_dir

  val sub_dirs : t -> sub_dir Filename.Array.Map.t
  val sub_dir_as_t : sub_dir -> t Memo.t

  module Make_map_reduce (M : Memo.S) (Outcome : Monoid) : sig
    (** Traverse sub-directories recursively, pass them to [f] and combine
        intermediate results into a single one via [M.combine]. *)
    val map_reduce
      :  t
      -> traverse:Source_dir_status.Set.t
      -> trace_event_name:string
      -> f:(t -> Outcome.t M.t)
      -> Outcome.t M.t
  end

  val sub_dir_names : t -> Filename.Array.Set.t
  val status : t -> Source_dir_status.t

  (** Return the contents of the dune (or jbuild) file in this directory *)
  val dune_file : t -> Dune_file.t option

  (** Return the project this directory is part of *)
  val project : t -> Dune_project.t

  val to_dyn : t -> Dyn.t
end

(** A source tree value. Currently every [t] reads from the workspace
    filesystem; the value-level abstraction is the substrate for letting a
    context have a different backing (git-tree-rooted, fetched archive, etc.)
    in the future. *)
type t

(** The default source tree, backed by the workspace filesystem. *)
val default : t

(** [of_external_root root] is a source tree whose contents live at the
    external filesystem path [root]. The same [Path.Source.t] identities
    are used for directories inside the tree — they're interpreted
    relative to [root] for filesystem reads.

    Defaults to [read_only = true]: the tree is assumed to belong to
    something the user isn't editing in place (e.g. a fetched dependency
    or a checkout managed by some other tool). Pass [~read_only:false]
    when the external location is genuinely writable, such as another
    project on the local filesystem that should still accept
    promotions. *)
val of_external_root : ?read_only:bool -> Path.External.t -> t

(** [read_only t] is [true] when this source tree is not user-editable —
    e.g., backed by a git sha or a fetched archive. Such trees are
    treated as fully vendored: warnings/alerts are suppressed in
    compilation flags, packages are filtered out of the workspace list,
    and rules-layer code should not emit promotion rules into them. *)
val read_only : t -> bool

(** [for_context ctx] returns the [Source_tree.t] associated with the
    build context [ctx]. Rules-layer code that generates rules for a
    specific context should query the source tree this way rather than
    falling back to [default], so that the per-context source-tree
    backing is observed once contexts can diverge. *)
val for_context : Context_name.t -> t Memo.t

(** Set the callback used to resolve [for_context]. Called once at build
    system initialisation. *)
val set_for_context_callback : (Context_name.t -> t Memo.t) -> unit

val root : t -> Dir.t Memo.t

module Make_map_reduce_with_progress (M : Memo.S) (Outcome : Monoid) : sig
  (** Traverse starting from the root and report progress in the status line *)
  val map_reduce
    :  t
    -> traverse:Source_dir_status.Set.t
    -> trace_event_name:string
    -> f:(Dir.t -> Outcome.t M.t)
    -> Outcome.t M.t
end

val find_dir : t -> Path.Source.t -> Dir.t option Memo.t

(** [find_excluded_ancestor path] is the ancestor of [path] that was excluded by
    a dirs stanza, if any. *)
val find_excluded_ancestor : t -> Path.Source.t -> (Path.Source.t * Loc.t) option Memo.t

(** [nearest_dir t fn] returns the directory with the longest path that is an
    ancestor of [fn]. *)
val nearest_dir : t -> Path.Source.t -> Dir.t Memo.t

val files_of : t -> Path.Source.t -> Path.Source.Set.t Memo.t

(** [file_exists path] is [true] iff [path] is a file in the source tree, taking
    into account [(files ...)] and other filtering applied by [dune] files. *)
val file_exists : t -> Path.Source.t -> bool Memo.t

(** [true] iff the path is a vendored directory *)
val is_vendored : t -> Path.Source.t -> bool Memo.t

(** [nearest_vcs t fn] returns the version control system with the longest root
    path that is an ancestor of [fn]. *)
val nearest_vcs : t -> Path.Source.t -> Vcs.t option Memo.t
