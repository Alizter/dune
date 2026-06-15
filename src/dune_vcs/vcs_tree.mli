(** A live view on the file tree at a specific revision of a VCS
    repository. Backend-agnostic; resolution and read operations
    dispatch on the underlying [Vcs.Kind.t].

    [Vcs_tree] is used by [Source_tree.of_vcs_tree] (in [src/source]) to
    back a context's source tree by an immutable revision rather than
    the on-disk working tree. *)

open Stdune

type t

(** Resolve a user-supplied rev *or revset/range* against the VCS at
    [root]. The string is passed verbatim to the backend's resolver — for
    Git, [git rev-parse]/[git rev-list]; for Hg, [hg log -r]. Returns
    one [t] per resolved commit, in repository order (oldest first for
    ranges). Errors if [rev] does not resolve. *)
val resolve_set : Vcs.t -> rev:string -> t list Fiber.t

(** Stable, content-addressable identifier for the rev (commit SHA for
    git, changeset hash for hg). Suitable for keying the staging cache. *)
val rev_id : t -> string

(** The backend kind that produced this view. *)
val kind : t -> Vcs.Kind.t

(** [list_dir t dir] enumerates the immediate children of [dir] at this
    rev. [dir] is interpreted relative to the repo root; [Path.Source.root]
    is the tree's top level. *)
val list_dir
  :  t
  -> Path.Source.t
  -> [ `File of Filename.t | `Dir of Filename.t ] list Fiber.t

(** [read_file t path] reads the bytes of [path] at this rev. Errors if
    [path] does not exist in the tree. *)
val read_file : t -> Path.Source.t -> string Fiber.t

(** [blob_sha t path] is the backend's content-hash for [path] at this
    rev (a git blob sha, etc.). [None] if [path] is not a file in the
    tree. Stable across invocations; suitable for use as a build-system
    dep digest without going through filesystem stat / digest. *)
val blob_sha : t -> Path.Source.t -> string option

(** Flat list of every file path in the rev's tree, in lexicographic
    order. Used by stagers that need to materialise every tracked file
    up front. *)
val files : t -> Path.Source.t list
