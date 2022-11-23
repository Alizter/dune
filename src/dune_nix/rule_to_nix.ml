open Import

let translate
    ({ id : Dune_engine.Rule.Id.t
     ; dir : Path.Build.t
     ; deps : Dune_engine.Dep.Set.t
     ; expanded_deps : Path.Set.t
     ; targets =
         { Dune_engine.Targets.Validated.files = file_targets
         ; dirs = dir_targets
         }
     ; context : Dune_engine.Build_context.t option
     ; action : Dune_engine.Action.t
     } :
      Dune_engine.Reflection.Rule.t) =
  (* Not sure what this is for *)
  ignore id;
  (* this is just the directory of the rule, not very useful atm *)
  ignore dir;
  ignore deps;
  ignore context;
  Action_to_nix.translate ~expanded_deps ~file_targets ~dir_targets action
