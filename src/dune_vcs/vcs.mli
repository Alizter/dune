(** VCS handling *)

open Stdune

module Kind : sig
  type t =
    | Git
    | Hg

  val equal : t -> t -> bool
  val of_dir_name : Filename.t -> t option

  val of_dir_contents
    :  files:Filename.Array.Set.t
    -> dirs:_ Filename.Array.Map.t
    -> t option
end

type t =
  { root : Path.t
  ; kind : Kind.t
  }

val equal : t -> t -> bool
val to_dyn : t -> Dyn.t

(** Walk [start] and its parent directories looking for a VCS metadata
    directory ([.git] or [.hg]). Returns the deepest matching repo, or
    [None] if no VCS is detected. Does not stat or open the repo;
    callers downstream (e.g. [Vcs_tree]) are responsible for that. *)
val find_repo_root : Path.t -> t option

(** Nice description of the current tip *)
val describe : t -> needed_for:string -> string option Memo.t

(** String uniquely identifying the current head commit *)
val commit_id : t -> needed_for:string -> string option Memo.t

(** Short git SHA of the current head commit, or [None] if unavailable *)
val git_sha_short : t -> string option Memo.t

(** List of files committed in the repo *)
val files : t -> needed_for:string -> Path.Source.t list Memo.t

(** VCS commands *)
val git : Path.t Lazy.t

val git_for : needed_for:string -> Path.t
val hg : Path.t Lazy.t

(** Valid git exit codes *)
val git_accept : unit -> ('a, ('a, int) result) Dune_engine.Process.Failure_mode.t
