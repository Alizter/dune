open Import

(** A lazy trie of semantic path candidates. *)
type t

type directory

val opaque : directory
val expandable : t Memo.Lazy.t -> directory
val create : values:string list -> directories:(string * directory) list -> t

(** Complete [token] relative to [cwd]. The trie must be rooted at the source
    root. Empty directory subtrees are omitted. Each expandable directory is
    followed while it has a single candidate. *)
val candidates : t -> cwd:Path.Source.t -> token:string -> string list Memo.t
