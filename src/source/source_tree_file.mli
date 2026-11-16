open Import

(** Source files and directories as seen by source loading. A workspace file is
    read from the workspace. A mounted file has a logical path, used for source
    semantics and diagnostics, and is read from a backing path in the build
    directory. *)

module File : sig
  type t

  val workspace : Path.Source.t -> t
  val mounted : logical:Path.Build.t -> backing:Path.Build.t -> t
  val source_path : t -> Path.Local.t

  (** The logical path used by source semantics and diagnostics. *)
  val path : t -> Path.t

  (** The path the file is read from. *)
  val backing_path : t -> Path.t

  val as_workspace : t -> Path.Source.t option
  val parent_exn : t -> t
  val relative : t -> Loc.t -> string -> t
  val exists : t -> bool Memo.t
  val read : t -> string option Memo.t
  val equal : t -> t -> bool
  val diagnostic_name : t -> string
  val with_lexbuf_from_file : t -> f:(Lexing.lexbuf -> 'a) -> 'a Memo.t
end

module Dir : sig
  type t

  val workspace : Path.Source.t -> t
  val mounted : logical:Path.Build.t -> backing:Path.Build.t -> t
  val basename : t -> Filename.t
  val file : t -> Filename.t -> File.t
end
