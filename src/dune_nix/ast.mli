(** * Abstract syntax tree for Nix lang *)

(** Nix lang syntax tree *)
type t

val to_dyn : t -> Dyn.t

(** Pretty printer *)
val pp : ?indent:int -> t -> 'a Pp.t

(** ** Data types *)

(** Nix integer literal *)
val int : int -> t

(** Nix floating point literal *)
val float : float -> t

(** Nix boolean literal *)
val bool : bool -> t

(** Nix string literal *)
val string : string -> t

(** Nix path literal *)
val path : string -> t

(** Nix lists *)
val list : t list -> t

(** Nix attribute sets:
    [
    rec {
      inherit x;
      inherit (y) z;
      foo = 1;
      bar = "baz";
    }
    ]
    with optional decleration of [rec], [inherit] and [inherit (scope)]
    statements. *)
val attr :
     ?rec_:bool
  -> ?inherit_:string list
  -> ?inherit_from_scope:string * string list
  -> (string * t) list
  -> t

(** ** Nix language constructs *)

(** Let statement:
    [
    let
      foo = "foz";
      bar = "baz";
    in
      foo + bar
    ]
    with optional decleration of [inherit] and [inherit (scope)] statements. *)
val let_ :
     ?inherit_:string list
  -> ?inherit_from_scope:string * string list
  -> (string * t) list
  -> t
  -> t

(** Nix if statments: [if ... then ... else ...]. *)
val if_then_else : t -> t -> t -> t

(** Nix functions [x: y]. *)
val fun_ : string -> t -> t

(** Nix functions with set pattern: [x@{a, b. ...}: y] where the [@] and [...]
    are optional. *)
val fun_set :
     ?at:string
  -> [ `A of string | `O of string * t ] list
  -> ?ellipsis:bool
  -> t
  -> t

(** Nix function application: [f x]. *)
val fun_app : t -> t -> t

(** Nix assertion statement *)
val assert_ : t -> t -> t

(** Nix with statement *)
val with_ : t -> t -> t
