open Import

(** Add revdep alias rules (@revdep, @revdep-check, @revdep-runtest,
    @revdep-install) for a directory. These aliases build all reverse
    dependencies of libraries defined in the directory. *)
val add : sctx:Super_context.t -> dir:Path.Build.t -> unit Memo.t

module Dependents : sig
  type t =
    { libs : Lib.Set.t
    ; dirs : Path.Build.Set.t
    }

  (** Given a list of libraries, return all stanzas that depend on them:
      - [libs]: library stanzas that depend on the given libs
      - [dirs]: directories containing executable/test stanzas that depend on them *)
  val find : Context_name.t -> Lib.t list -> t Memo.t
end
