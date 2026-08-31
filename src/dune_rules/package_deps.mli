(** Materialize dependencies on packages for actions. *)

open Import

type dependency =
  { loc : Loc.t
  ; name : Package.Name.t
  }

(** Register a dependency on one package without constructing an action
    environment. *)
val depend
  :  Context_name.t
  -> dune_version:Dune_lang.Syntax.Version.t
  -> dependency
  -> unit Action_builder.t

(** Materialize one immediate package set. The returned environment points at a
    single install layout for all local packages in the set. Evaluating the
    builder also registers dependencies on local, opaque, and installed package
    artifacts. *)
val materialize
  :  Context_name.t
  -> dune_version:Dune_lang.Syntax.Version.t
  -> dependency list
  -> Env.t Action_builder.t
