open Import

type t =
  { file_paths : Path.Build.t list
  ; directory_paths : Path.Build.t list
  ; aliases : Dune_engine.Alias.Name.t list
  }

(** Return the file targets, directory targets, and aliases generated while
    loading a build directory. *)
val in_dir : Path.Build.t -> t Memo.t

val direct_files : t -> dir:Path.Build.t -> Filename.t list
val direct_directories : t -> dir:Path.Build.t -> Filename.t list
