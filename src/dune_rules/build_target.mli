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

(** Exclude file targets that also exist in the source tree. *)
val file_paths_excluding_sources : t -> Path.Build.t list Memo.t

val direct_files_excluding_sources : t -> dir:Path.Build.t -> Filename.t list Memo.t

(** Complete build targets and aliases relative to [cwd]. Alias tokens start
    with [@] or [@@]. Unambiguous directory chains are completed in full. *)
val candidates : cwd:Path.Source.t -> token:string -> string list Memo.t
