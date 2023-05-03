open Stdune

(** This is the info sent to a Dune_console backend when a process is started. *)

type t =
  { pid : Pid.t
  ; started_at : float
  ; ended_at : float option
  ; prog_str : string
  }
