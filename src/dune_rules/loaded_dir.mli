open Import

type t

val create : project:Loaded_project.t -> source_dir:Path.Local.t -> t
val project : t -> Loaded_project.t
val source_dir : t -> Path.Local.t
val output_dir : t -> Path.Build.t
