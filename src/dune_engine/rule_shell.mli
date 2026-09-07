open Import

(** Preparation of a rule action for an interactive [dune shell] session. *)

type direct_process =
  { program : Path.t
  ; args : string list
  ; dir : Path.t
  ; env : Env.t
  }

type t =
  { dir : Path.t
  ; shell_env : Env.t
    (** The entry environment after common leading action wrappers and the
        final Dune temporary-directory injection. *)
  ; replay_env : Env.t
    (** The base action environment. Scoped wrappers remain in [action]; the
        Dune temporary-directory injection is already present. *)
  ; sandbox_dir : Path.Build.t option
  ; use_sandbox_policy : bool
    (** Whether replay processes need an OS sandbox policy for [sandbox_dir]. *)
  ; sandbox_mode : Sandbox_mode.some option
  ; action : Action.t
  ; direct_process : direct_process option
    (** Literal process metadata using the entry directory and environment. *)
  ; targets : Targets.Validated.t
  ; rule_digest : Digest.t
  }

(** Build and evaluate all prerequisites of [rule], prepare the rule's action
    in its normally selected execution location, and run [f] instead of the
    action. Existing declared targets are removed as they are before ordinary
    action execution. The selected action is not executed and its outputs are
    not extracted, cached, or promoted. The execution location and the rule's
    action locks remain owned by the build system until [f] returns. *)
val with_ : Rule.t -> f:(t -> 'a Fiber.t) -> 'a Memo.t
