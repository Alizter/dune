open! Stdune

(** Convert a [Lexing.position] to a [Csexp.t]. *)
val pos_to_sexp : Lexing.position -> Csexp.t

(** Convert a location to a [Csexp.t]. *)
val loc_to_sexp : Loc.t -> Csexp.t

module Module : sig
  (** Tokens for modules consist of a location [loc] of the token and a string
      [logical_name] for the value. *)
  type t

  (** Construct a [Module.t] with given location and logical name. *)
  val make : Loc.t -> string -> t

  (** Displays the [logical_name] of a module. *)
  val to_string : t -> string

  (** Convert a module to a [Csexp.t] containing the location and
      [logical_name]. *)
  val to_sexp : t -> Csexp.t
end

(** Abstract type of lexed dependency tokens. *)
type t

(** Name of the file the tokens were lexed in. *)
val get_filename : t -> string

(** Empty token. *)
val empty : t

(** Set the filename of a token. *)
val set_filename : t -> string -> t

(** Add a list of modules to a token sharing the same prefix. *)
val add_from_list : t -> Module.t option -> Module.t list -> t

(** Add a single module to a token. *)
val add_require : t -> Module.t -> t

(** Add a list of modules to a token. *)
val add_require_list : t -> Module.t list -> t

(** Add a list of OCaml modules to a token. *)
val add_declare_list : t -> Module.t list -> t

(** Add a physical load to a token. *)
val add_load : t -> Loc.t -> string -> t

(** Add an extra dependency to a token. *)
val add_extrdep : t -> Loc.t -> Module.t -> string -> t

(** Convert a token to a string. This will print a readable document. *)
val to_string : t -> string

(** Convert the token to a [Csexp.t]. *)
val to_sexp : t -> Csexp.t

(** Sort the entries of the token unique upto non-location data. *)
val sort_uniq : t -> t

