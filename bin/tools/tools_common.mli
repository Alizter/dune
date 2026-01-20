open Import

val env_command : unit Cmd.t

(** Generic tool commands for arbitrary packages *)

(** Terms for generic tool commands (used as defaults in command groups) *)
val generic_exec_term : unit Term.t

val generic_lock_term : unit Term.t
val generic_which_term : unit Term.t
val generic_list_term : unit Term.t
val generic_remove_term : unit Term.t

(** Execute any opam package as a tool *)
val generic_exec_command : unit Cmd.t

(** Lock any opam package as a tool (always re-solves, like dune pkg lock) *)
val generic_lock_command : unit Cmd.t

(** Print the path to any tool's executable *)
val generic_which_command : unit Cmd.t

(** List all locked tools and their versions *)
val generic_list_command : unit Cmd.t

(** Remove a locked tool (all versions or specific version) *)
val generic_remove_command : unit Cmd.t
