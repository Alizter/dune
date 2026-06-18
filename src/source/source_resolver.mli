(** A resolver tells callers how to read bytes for a [Path.Source.t].

    Filesystem and external-mount backings supply a [resolve] closure
    mapping source paths to a real [Path.Outside_build_dir.t]; the
    [file_exists] / [with_lexbuf_from_file] operations default to
    [Fs_memo] reads at the resolved path.

    Vcs and build-dir backings cannot represent bytes as a filesystem
    path. They install a vestigial [resolve] (returning [In_source_dir
    p] so callers branching on [is_workspace] behave consistently) and
    supply custom [file_exists] / [with_lexbuf_from_file] closures
    that read directly from the backing — git blob bytes for vcs,
    [Build_system.with_file] for build-dir mounts. This is what makes
    [(include foo.inc)] resolve against the mount's bytes rather
    than the workspace source root.

    Each value carries a stable [Id.t] so callers can test equality
    reliably (e.g. "is this the workspace resolver?") without relying
    on physical equality of closures. *)

open Import

type t

(** The default resolver, mapping every [Path.Source.t] to its
    workspace-relative [In_source_dir] interpretation; reads through
    [Fs_memo]. *)
val workspace : t

(** Build a resolver from a filesystem-path translator. Reads are
    routed through [Fs_memo] at the translated path. *)
val create_fs : (Path.Source.t -> Path.Outside_build_dir.t) -> t

(** Polymorphic [with_lexbuf_from_file] closure wrapper. Callers
    construct one as [{ f = (fun p ~f -> ...) }] so the record field
    keeps universal polymorphism. *)
type with_lexbuf =
  { f : 'a. Path.Source.t -> f:(Lexing.lexbuf -> 'a) -> 'a Memo.t }

(** Build a resolver with a custom read mechanism for [(include ...)]
    resolution. The supplied [resolve] is vestigial — used only by
    callers that need a [Path.Outside_build_dir.t] view; reads go
    through the supplied closures. *)
val create_custom
  :  resolve:(Path.Source.t -> Path.Outside_build_dir.t)
  -> file_exists:(Path.Source.t -> bool Memo.t)
  -> with_lexbuf_from_file:with_lexbuf
  -> t

val resolve : t -> Path.Source.t -> Path.Outside_build_dir.t
val file_exists : t -> Path.Source.t -> bool Memo.t

val with_lexbuf_from_file
  :  t
  -> Path.Source.t
  -> f:(Lexing.lexbuf -> 'a)
  -> 'a Memo.t

val equal : t -> t -> bool

(** [is_workspace t] is [true] iff [t == workspace]. *)
val is_workspace : t -> bool
