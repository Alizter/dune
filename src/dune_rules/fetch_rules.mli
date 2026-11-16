open Import

(** Fetch remote sources from the revision store or http.
    Note: this module does not handle source on local disk *)

val context : Build_context.t

module Kind : sig
  type t =
    | File
    | Dir
end

(** Where a source is fetched to. *)
val make_target : kind:Kind.t -> Dune_pkg.Source.t -> Path.Build.t

(** The files and directories of a local source directory. *)
val local_source_contents
  :  loc:Loc.t
  -> Path.Outside_build_dir.t
  -> (Path.Local.t list * Path.Local.t list) Memo.t

val fetch
  :  target:Path.Build.t
  -> Kind.t
  -> Dune_pkg.Source.t
  -> Action.Full.t With_targets.t

val gen_rules : string list -> Build_config.Gen_rules.t Memo.t
