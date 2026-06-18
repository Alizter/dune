(** First stage of evaluating a dune file. Handles [include], [subdir]
    and the various directory status stanzas. *)

open Import

val statically_evaluated_stanzas : string list
val fname : Filename.t

type kind =
  | Plain
  | Ocaml_script

type t

val to_dyn : t -> Dyn.t

(** The contents of the dune file without the OCaml syntax *)
val get_static_sexp : t -> Dune_lang.Ast.t list

val kind : t -> kind

(** The path to the dune file. If [kind = Ocaml_script], then this always
    returns [Some p] where [p] is path to the script *)
val path : t -> Path.Source.t option

val sub_dir_status : t -> Source_dir_status.Spec.t

(** The location of the (dirs ...) stanza if present *)
val dirs_stanza_loc : t -> Loc.t option

(** Snapshot of the backing's resolver. Callers that re-resolve
    [(include ...)] directives on the persisted sexps (notably
    [src/dune_rules/dune_file.ml]'s [parse_stanzas]) must pass this
    to [Include_stanza] so the resolution goes through the same
    backing (filesystem, vcs, or build-dir) as the original load. *)
val resolver : t -> Source_resolver.t

module Files : sig
  type t

  val default : t
  val eval : t -> files:Filename.Array.Set.t -> Filename.Array.Set.t
end

val files : t -> Files.t

(** Directories introduced via [(subdir ..)] *)
val sub_dirnames : t -> Filename.Array.Set.t

(** [load] reads the dune file at [dir] (workspace-relative).

    [byte_provider] returns the bytes of a given source path; the dune
    file is parsed from those bytes via [Lexing.from_string]. For a
    filesystem-backed source tree, callers pass a closure that delegates
    to [Fs_memo.file_contents]; for a non-filesystem backing (e.g. a
    git tree) the closure reads from the backend directly without
    materialising the file on disk.

    [resolver] supplies the per-backing read closures used by
    [(include ...)] resolution AND the [Path.Source.t ->
    Path.Outside_build_dir.t] translation used by the missing-dune-project
    warning (which fires only when [resolver] is the workspace one). *)
val load
  :  ?resolver:Source_resolver.t
  -> byte_provider:(Path.Source.t -> string Memo.t)
  -> dir:Path.Source.t
  -> Source_dir_status.t
  -> Dune_project.t
  -> files:Filename.Array.Set.t
  -> parent:t option
  -> t option Memo.t
