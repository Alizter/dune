(** A collection of rules across a known finite set of directories *)

open! Import
module Action_builder := Action_builder0

(** Represent a set of rules producing files in a given directory *)
module Dir_rules : sig
  type t

  val empty : t
  val union : t -> t -> t

  module Alias_spec : sig
    type item =
      | Deps of unit Action_builder.t
      | (* Execute an action. You can think of [action t] as a convenient way of
           declaring an anonymous build rule and depending on its outcome. While
           this action does not produce any value observable by the rest of the
           build rules, the action can fail. So its outcome is success or
           failure. This mechanism is commonly used for attaching tests to an
           alias.

           Note that any dependency declared in [t] is treated as a dependency
           of the action returned by [t], rather than anything that depends on
           the alias containing the action.

           When passing [--force] to Dune, these are exactly the actions that
           will be re-executed. *)
        Action of Rule.Anonymous_action.t Action_builder.t

    type t = { expansions : (Loc.t * item) Appendable_list.t } [@@unboxed]
  end

  (** A ready to process view of the rules of a directory *)
  type ready =
    { rules : Rule.t list
    ; aliases : Alias_spec.t Alias.Name.Map.t
    }

  val consume : t -> ready
  val is_subset : t -> of_:t -> bool
  val is_empty : t -> bool
  val to_dyn : t -> Dyn.t
end

(** A value of type [t] holds a set of rules for multiple directories *)
type t

val to_map : t -> Dir_rules.t Path.Build.Map.t

module Produce : sig
  (* CR-someday aalekseyev: the below comments are not quite right *)

  (** Add a rule to the system. This function must be called from the
      [gen_rules] callback. All the target of the rule must be in the same
      directory.

      Assuming that [gen_rules ~dir:a] calls [add_rule r] where [r.dir] is [b],
      one of the following assumption must hold:

      - [a] and [b] are the same - [gen_rules ~dir:b] calls [load_dir ~dir:a]

      The call to [load_dir ~dir:a] from [gen_rules ~dir:b] declares a directory
      dependency from [b] to [a]. There must be no cyclic directory
      dependencies. *)
  val rule : Rule.t -> unit Memo.t

  module Alias : sig
    type t = Alias.t

    (** [add_deps alias ?loc deps] arrange things so that all the dependencies
        registered by [deps] are considered as a part of alias expansion of
        [alias]. *)
    val add_deps : t -> ?loc:Stdune.Loc.t -> unit Action_builder.t -> unit Memo.t

    (** [add_action alias ~loc action] arrange things so that [action]
        is executed as part of the build of alias [alias]. *)
    val add_action : t -> loc:Loc.t -> Action.Full.t Action_builder.t -> unit Memo.t
  end
end

val implicit_output : t Memo.Implicit_output.t
val empty : t
val to_dyn : t -> Dyn.t
val union : t -> t -> t
val of_dir_rules : dir:Path.Build.t -> Dir_rules.t -> t
val of_rules : Rule.t list -> t
val produce : t -> unit Memo.t
val is_subset : t -> of_:t -> bool
val map_rules : t -> f:(Rule.t -> Rule.t) -> t
val collect : (unit -> 'a Memo.t) -> ('a * t) Memo.t
val collect_unit : (unit -> unit Memo.t) -> t Memo.t

(** returns [Dir_rules.empty] for non-build paths *)
val find : t -> Path.t -> Dir_rules.t

(** [prefix_rules prefix ~f] adds [prefix] to all the rules generated by [f] *)
val prefix_rules : unit Action_builder.t -> f:(unit -> 'a Memo.t) -> 'a Memo.t

(** [directory_targets t] returns all the directory targets generated by [t].
    The locations are of the rules that introduce these targets *)
val directory_targets : t -> Loc.t Path.Build.Map.t
