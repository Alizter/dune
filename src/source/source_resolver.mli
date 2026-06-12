(** A path resolver: a closure translating logical [Path.Source.t]
    identities to the physical [Path.Outside_build_dir.t] from which
    bytes are read. Each value carries a stable [Id.t] so callers can
    test equality reliably (e.g. "is this the workspace resolver?")
    without relying on physical equality of closures. *)

open Import

type t

(** The default resolver, mapping every [Path.Source.t] to its
    workspace-relative [In_source_dir] interpretation. *)
val workspace : t

val create : (Path.Source.t -> Path.Outside_build_dir.t) -> t
val resolve : t -> Path.Source.t -> Path.Outside_build_dir.t
val equal : t -> t -> bool

(** [is_workspace t] is [true] iff [t == workspace]. *)
val is_workspace : t -> bool
