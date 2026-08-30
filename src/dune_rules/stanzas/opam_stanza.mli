(** An opaque package recipe whose installed capabilities are discovered from
    its install cookie. *)

open Import

type origin =
  | User
  | Lock

type t =
  { loc : Loc.t
  ; origin : origin
  ; package : Package.t
  ; depends : (Loc.t * Package.Name.t) list
  ; build : Dune_pkg.Lock_dir.Build_command.t option
  ; install : Dune_lang.Action.t option
  ; depexts : Dune_pkg.Lock_dir.Depexts.t list
  ; exported_env : String_with_vars.t Dune_lang.Action.Env_update.t list
  }

val decode : t Dune_lang.Decoder.t
val target_dir : t -> dir:Path.Build.t -> Path.Build.t

include Stanza.S with type t := t
