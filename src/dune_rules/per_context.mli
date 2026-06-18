(** Allows defining data per context without initializing the entire context *)

open Import

type 'a t = Context_name.t -> 'a Memo.t

val create_by_name
  :  name:string
  -> (Context_name.t -> 'a Memo.t)
  -> (Context_name.t -> 'a Memo.t) Staged.t

val profile : Context_name.t -> Profile.t Memo.t
val valid : Context_name.t -> bool Memo.t
val list : unit -> Context_name.t list Memo.t

(** Internal contexts that share the same user-facing [Workspace.Context.t]
    as the given context, excluding itself. Used by the rules layer to
    coordinate cross-mount lookups (libraries, binaries, etc.). *)
val siblings : Context_name.t -> Context_name.t list Memo.t

(** Name of the user-facing [Workspace.Context.t] backing [ctx]. For
    user-facing contexts this is [ctx] itself; for sibling contexts
    (mounts, pkg-mounts, cross-targets) it is the workspace-declared
    parent. Returns [ctx] unchanged for unknown contexts. Used to
    redirect pkg lookups (toolchain, [%{pkg:...}]) so sibling
    contexts share the parent's build artefacts. *)
val user_facing : Context_name.t -> Context_name.t Memo.t
