open Import

module File : sig
  type t

  val workspace : Path.Source.t -> t
  val build : Path.Build.t -> t
  val source_path : t -> Source_path.t
  val path : t -> Path.t
  val as_workspace : t -> Path.Source.t option
  val relative : t -> Loc.t -> string -> t
  val read : t -> string option Memo.t
  val equal : t -> t -> bool
  val diagnostic_name : t -> string
  val to_dyn : t -> Dyn.t
end

module Dir : sig
  type t

  val workspace : Path.Source.t -> t
  val build : Path.Build.t -> t
  val source_path : t -> Source_path.t
  val path : t -> Path.t
  val basename : t -> Filename.t
  val file : t -> Filename.t -> File.t
end
