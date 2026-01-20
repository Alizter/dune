open Import

(** Returns the version from the current project's .ocamlformat file,
    if it exists *)
val version_of_current_project's_ocamlformat_config : unit -> Package_version.t option

(** Find the .ocamlformat file that applies to a given source directory.
    Searches upward from the directory until it finds one or reaches root. *)
val find_ocamlformat_config_for_dir : Path.Source.t -> Path.t option

(** Get the version from the .ocamlformat file that applies to a source directory.
    Searches upward from the directory until it finds a .ocamlformat file. *)
val version_for_dir : Path.Source.t -> Package_version.t option
