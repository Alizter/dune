(** Types exposed to end-user consumers of [dune_rpc.mli]. *)

module Loc : sig
  type t = Stdune.Lexbuf.Loc.t =
    { start : Lexing.position
    ; stop : Lexing.position
    }

  val start : t -> Lexing.position
  val stop : t -> Lexing.position
  val sexp : t Conv.value
end

val sexp_pp : 'a Conv.value -> 'a Pp.t Conv.value

module Target : sig
  type t =
    | Path of string
    | Alias of string
    | Library of string
    | Executables of string list
    | Preprocess of string list
    | Loc of Loc.t

  val sexp : t Conv.value
end

module Path : sig
  type t = string

  val dune_root : t
  val absolute : string -> t
  val relative : t -> string -> t
  val to_string_absolute : t -> string
  val sexp : t Conv.value
end

module Ansi_color : sig
  module RGB8 : sig
    type t = char

    val sexp : t Conv.value
  end

  module RGB24 : sig
    type t = int

    val sexp : t Conv.value
  end

  module Style : sig
    type t =
      | Fg_default
      | Fg_black
      | Fg_red
      | Fg_green
      | Fg_yellow
      | Fg_blue
      | Fg_magenta
      | Fg_cyan
      | Fg_white
      | Fg_bright_black
      | Fg_bright_red
      | Fg_bright_green
      | Fg_bright_yellow
      | Fg_bright_blue
      | Fg_bright_magenta
      | Fg_bright_cyan
      | Fg_bright_white
      | Fg_8_bit_color of RGB8.t
      | Fg_24_bit_color of RGB24.t
      | Bg_default
      | Bg_black
      | Bg_red
      | Bg_green
      | Bg_yellow
      | Bg_blue
      | Bg_magenta
      | Bg_cyan
      | Bg_white
      | Bg_bright_black
      | Bg_bright_red
      | Bg_bright_green
      | Bg_bright_yellow
      | Bg_bright_blue
      | Bg_bright_magenta
      | Bg_bright_cyan
      | Bg_bright_white
      | Bg_8_bit_color of RGB8.t
      | Bg_24_bit_color of RGB24.t
      | Bold
      | Dim
      | Italic
      | Underline

    val sexp : t Conv.value
  end
end

module User_message : sig
  module Style : sig
    type t =
      | Loc
      | Error
      | Warning
      | Kwd
      | Id
      | Prompt
      | Hint
      | Details
      | Ok
      | Debug
      | Success
      | Ansi_styles of Ansi_color.Style.t list

    val to_user_message_style : t -> Stdune.User_message.Style.t
    val of_user_message_style : Stdune.User_message.Style.t -> t
  end
end

module Diagnostic : sig
  type severity =
    | Error
    | Warning

  module Promotion : sig
    type t =
      { in_build : string
      ; in_source : string
      }

    val in_build : t -> string
    val in_source : t -> string
    val sexp : t Conv.value
  end

  module Id : sig
    type t

    val compare : t -> t -> Ordering.t
    val hash : t -> int
    val create : int -> t
    val sexp : t Conv.value
  end

  module Related : sig
    type t =
      { message : User_message.Style.t Pp.t
      ; loc : Loc.t
      }

    val message : t -> unit Pp.t
    val message_with_style : t -> User_message.Style.t Pp.t
    val loc : t -> Loc.t
    val sexp : t Conv.value
  end

  type t =
    { targets : Target.t list
    ; id : Id.t
    ; message : User_message.Style.t Pp.t
    ; loc : Loc.t option
    ; severity : severity option
    ; promotion : Promotion.t list
    ; directory : string option
    ; related : Related.t list
    }

  val related : t -> Related.t list
  val id : t -> Id.t
  val loc : t -> Loc.t option
  val message : t -> unit Pp.t
  val message_with_style : t -> User_message.Style.t Pp.t
  val severity : t -> severity option
  val promotion : t -> Promotion.t list
  val targets : t -> Target.t list
  val directory : t -> string option
  val to_dyn : t -> Dyn.t
  val to_user_message : t -> Stdune.User_message.t

  module Event : sig
    type nonrec t =
      | Add of t
      | Remove of t

    val to_dyn : t -> Dyn.t
    val sexp : t Conv.value
  end

  val sexp : t Conv.value
end

module Progress : sig
  type t =
    | Waiting
    | In_progress of
        { complete : int
        ; remaining : int
        ; failed : int
        }
    | Failed
    | Interrupted
    | Success

  val sexp : t Conv.value
end

module Message : sig
  type t =
    { payload : Csexp.t option
    ; message : string
    }

  val payload : t -> Csexp.t option
  val message : t -> string
  val sexp : t Conv.value
  val to_sexp_unversioned : t -> Csexp.t
end

module Job : sig
  module Id : sig
    type t

    val compare : t -> t -> Ordering.t
    val hash : t -> int
    val create : int -> t
    val sexp : t Conv.value
  end

  type t =
    { id : Id.t
    ; pid : int
    ; description : unit Pp.t
    ; started_at : float
    }

  val id : t -> Id.t
  val pid : t -> int
  val description : t -> unit Pp.t
  val started_at : t -> float

  module Event : sig
    type nonrec t =
      | Start of t
      | Stop of Id.t

    val sexp : t Conv.value
  end
end
