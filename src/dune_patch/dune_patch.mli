open Stdune
open Dune_engine

val action : patch:Path.t -> Action.t

module For_tests : sig
  val exec : patch:Path.t -> dir:Path.t -> unit Fiber.t
end
