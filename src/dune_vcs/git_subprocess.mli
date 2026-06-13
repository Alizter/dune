(** Low-level git subprocess helpers for reading from an existing local
    repository. Operates on the user's own [.git]; does not share state
    with [Dune_pkg.Rev_store]'s managed bare repo. *)

open Stdune

type t

val create : root:Path.t -> t

(** Resolve [rev] to a single commit sha via [git rev-parse]. Returns
    [None] if [rev] does not resolve to a single commit (e.g., the input
    is a range or revset rather than a single rev). *)
val rev_parse_single : t -> string -> string option Fiber.t

(** Expand [rev_arg] to a list of commit shas via [git rev-list]. Accepts
    ranges ([A..B]), symmetric difference ([A...B]), refs, etc. Returns
    [None] if the argument doesn't resolve at all. *)
val rev_list : t -> string -> string list option Fiber.t

(** [ls_tree_recursive t ~commit] lists every blob in [commit]'s tree as
    [(path, sha)] pairs. *)
val ls_tree_recursive : t -> commit:string -> (Path.Local.t * string) list Fiber.t

(** [cat_file_blob t ~commit ~path] reads the bytes of [path] in [commit]. *)
val cat_file_blob : t -> commit:string -> path:Path.Local.t -> string Fiber.t
