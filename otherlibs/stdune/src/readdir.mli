(** Efficient directory listing with kinds. *)

(** [read_directory_with_kinds] is similar to [Sys.readdir], while additionally
    returning kinds of the filesystem entries. *)
val read_directory_with_kinds
  :  string
  -> ((string * File_kind.t) list, Unix_error.Detailed.t) Result.t

(** [read_directory_with_kinds d] returns all the filesystem entries in [d]
    except for "." and "..", similar to [Sys.readdir]. *)
val read_directory : string -> (string list, Unix_error.Detailed.t) Result.t

(** Windows-only: delete a file using the wide (UTF-16) API. *)
val win32_unlink : string -> unit

(** Windows-only: remove a directory using the wide (UTF-16) API.
    Also works for removing junction/symlink reparse points. *)
val win32_rmdir : string -> unit
