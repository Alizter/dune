open Stdune

type 'a t

module Remote : sig
  type t

  val update : t -> unit Fiber.t
  val default_branch : t -> string option Fiber.t

  module At_rev : sig
    type t

    val content : t -> Path.Local.t -> string option Fiber.t
    val directory_entries : t -> Path.Local.t -> Path.Local.t list Fiber.t
    val equal : t -> t -> bool
    val repository_id : t -> Repository_id.t
  end

  val rev_of_name : t -> name:string -> At_rev.t option Fiber.t
  val rev_of_repository_id : t -> Repository_id.t -> At_rev.t option Fiber.t
end

val create : dir:Path.t -> [ `Uninitialized ] t
val initialize : [ `Uninitialized ] t -> [ `Initialized ] t Fiber.t
val add_repo : [ `Initialized ] t -> source:string -> Remote.t Fiber.t
