open Import

module File : sig
  type t

  val dummy : t
  val of_source_path : Path.Source.t -> (t, Unix_error.Detailed.t) result Memo.t
  val of_path : Path.Outside_build_dir.t -> (t, Unix_error.Detailed.t) result Memo.t

  module Map : Map.S with type key = t
end

type t

val empty : t
val dirs : t -> File.t Filename.Array.Map.t
val files : t -> Filename.Array.Set.t
val to_dyn : t -> Dyn.t
val of_source_path : Path.Source.t -> (t, Unix_error.Detailed.t) result Memo.t

(** Like [of_source_path], but reads the directory contents from
    [physical] (an arbitrary outside-build-dir location). [path_for_hint]
    is the [Path.Source.t] identity carried in any user-facing diagnostic
    — for workspace-rooted source trees this is the same as the physical
    path, for externally-rooted source trees it's the path within the
    source tree's logical namespace. *)
val of_outside_build_dir
  :  path_for_hint:Path.Source.t
  -> physical:Path.Outside_build_dir.t
  -> (t, Unix_error.Detailed.t) result Memo.t
