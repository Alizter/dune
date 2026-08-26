open Import

type t

val create : snapshot:Dune_pkg.Source_snapshot.t -> root:Path.Build.t -> t
val root : t -> Path.Build.t
val id : t -> Dune_digest.t
val manifest_digest : t -> Dune_digest.t
val equal : t -> t -> bool
val source_path : t -> Path.Local.t -> Path.Build.t
val local_path : t -> Path.Build.t -> Path.Local.t option
val readdir : t -> Path.Local.t -> [ `Dir | `File ] Filename.Map.t Memo.t
val read_file : t -> Path.Local.t -> string Memo.t
val file_path : t -> Path.Local.t -> Path.t
val file_exists : t -> Path.Local.t -> bool Memo.t
val diagnostic_name : t -> Path.Local.t -> string
val to_dyn : t -> Dyn.t
