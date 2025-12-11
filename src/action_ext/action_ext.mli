open Stdune

(** Create an action extension that always returns Done after executing. *)
module Make (S : sig
    type ('path, 'target) t

    val name : string
    val version : int
    val is_useful_to : memoize:bool -> bool
    val encode : ('p, 't) t -> ('p -> Sexp.t) -> ('t -> Sexp.t) -> Sexp.t
    val bimap : ('a, 'b) t -> ('a -> 'x) -> ('b -> 'y) -> ('x, 'y) t

    val action
      :  (Path.t, Path.Build.t) t
      -> ectx:Dune_engine.Action.context
      -> eenv:Dune_engine.Action.env
      -> unit Fiber.t
  end) : sig
  val action : (Path.t, Path.Build.t) S.t -> Dune_engine.Action.t
end

(** Create an action extension that returns the action's result directly. *)
module Make_full (S : sig
    type ('path, 'target) t

    val name : string
    val version : int
    val is_useful_to : memoize:bool -> bool
    val encode : ('p, 't) t -> ('p -> Sexp.t) -> ('t -> Sexp.t) -> Sexp.t
    val bimap : ('a, 'b) t -> ('a -> 'x) -> ('b -> 'y) -> ('x, 'y) t

    val action
      :  (Path.t, Path.Build.t) t
      -> ectx:Dune_engine.Action.context
      -> eenv:Dune_engine.Action.env
      -> Dune_engine.Done_or_more_deps.t Fiber.t
  end) : sig
  val action : (Path.t, Path.Build.t) S.t -> Dune_engine.Action.t
end
