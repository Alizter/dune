open Import

(** The targets command lists all the targets available in the given directory,
    defaulting to the current working direcctory. *)
val command : unit Cmd.t
