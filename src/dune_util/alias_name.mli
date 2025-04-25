open Stdune

(** An [Alias_name.t] is a validated [string] that is used to denote an alias. It is used
    to ensure that the alias name is valid and does not contain any invalid characters
    that can intefere with parsing. *)
type t

(** [Alias_name.of_string_opt] validates a given string as an alias name. *)
val of_string_opt : string -> t option

val of_string : string -> t
val to_string : t -> string

(** [Alias_name.parse_local_path (loc, local_path)] parses a local path denoting an alias
    in a subdirectory and returns a tuple containing the local path and the alias name. *)
val parse_local_path : Loc.t * Path.Local.t -> Path.Local.t * t

include Comparable_intf.S with type key := t

val to_dyn : t -> Dyn.t
val equal : t -> t -> bool
val compare : t -> t -> Ordering.t
val hash : t -> int
