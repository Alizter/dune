include module type of struct
  include Stdlib.Char
end

(** Check if a character belongs to the set [{'0'..'9'}]. *)
val is_digit : t -> bool

(** Check if a character belongs to the set [{'0'..'9', 'a'..'f'}]. *)
val is_lowercase_hex : t -> bool

(** [of_int i] converts an integer in the range [0..255] to [Some] character and
    [None] otherwise. *)
val of_int : int -> t option
