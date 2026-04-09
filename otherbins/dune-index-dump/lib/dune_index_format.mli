open Stdune

type lid =
  { name : string
  ; loc : Loc.t
  }

type uid_entry =
  { kind : string (** "intf" or "impl" *)
  ; comp_unit : string (** e.g. "Mylib__Helper" *)
  ; id : int
  ; locs : lid list (** all locations where this UID appears *)
  ; related_group_size : int (** >2 indicates re-export chain; 0 for impl *)
  ; impl_id : int option (** for intf: the related impl UID's id *)
  }

val lid_to_sexp : lid -> Sexp.t
val lid_of_sexp : Sexp.t -> lid option
val uid_entry_to_sexp : uid_entry -> Sexp.t
val uid_entry_of_sexp : Sexp.t -> uid_entry option
val to_sexp : uid_entry list -> Sexp.t
val of_sexp : Sexp.t -> uid_entry list
val of_csexp_string : string -> uid_entry list
