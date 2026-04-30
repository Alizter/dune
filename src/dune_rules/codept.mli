(** Module dependency discovery using codept.

    Alternative to ocamldep that uses anonymous actions
    (execute_action_stdout) to run codept per file and parse stdout directly.
    No intermediate files or transitive closure computation. *)

open Import

val deps_of
  :  sandbox:Sandbox_config.t
  -> modules:Modules.With_vlib.t
  -> sctx:Super_context.t
  -> dir:Path.Build.t
  -> ml_kind:Ml_kind.t
  -> for_:Compilation_mode.t
  -> Module.t
  -> Module.t list Action_builder.t
