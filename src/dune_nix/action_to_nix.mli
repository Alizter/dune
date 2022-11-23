open Import

val translate :
     expanded_deps:Path.Set.t
  -> file_targets:Path.Build.Set.t
  -> dir_targets:Path.Build.Set.t
  -> Dune_engine.Action.t
  -> Ast.t
