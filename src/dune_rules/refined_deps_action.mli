(** Action extension for computing refined dependencies.

    This action runs ocamlobjinfo on a compiled object file (.cmo/.cmx),
    extracts the imported interfaces, maps them to .cmi file paths using
    a pre-computed mapping, and writes the paths to an output file. *)

open Import

val action
  :  ocamlobjinfo:Path.t
  -> input:Path.t
  -> output:Path.Build.t
  -> mapping:(Module_name.Unique.t * Path.t) list
  -> Dune_engine.Action.t
