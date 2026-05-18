open Import

(** Writes the cram-commands script (the source [.t] file with output and
    comment lines stripped) to stdout. *)
val make_script
  :  src:Path.t
  -> conflict_markers:Cram_stanza.Conflict_markers.t
  -> Action.t

(** Executes [commands] (the output of [make_script]) and writes a serialised
    [command_out list] of per-command results to stdout. *)
val run
  :  src:Path.t
  -> dir:Path.t
  -> commands:string
  -> timeout:(Loc.t * Time.Span.t) option
  -> setup_scripts:Path.t list
  -> Cram_stanza.Shell.t
  -> Action.t

(** Produces a [.corrected] diff if [src] needs to be updated. [run_output] is
    the serialised result produced by [run]. *)
val diff : src:Path.t -> run_output:string -> Action.t

(** Corresponds the user written cram action *)
val action : Path.t -> Action.t

module For_tests : sig
  val cram_stanzas : Lexing.lexbuf -> (Loc.t * string list Cram_lexer.block) list
  val dyn_of_block : string list Cram_lexer.block -> Dyn.t
end
