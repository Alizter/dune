open Import

val term :
     (   Dune_rules.Main.build_system
      -> Path.Source.t
      -> Path.t
      -> string list Action_builder.t)
  -> unit Term.t
