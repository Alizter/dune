(** Windows long path support detection.

    On non-Windows platforms, all functions are no-ops. *)

open Import

(** 260 — the Windows MAX_PATH limit *)
val max_path : int

(** Check if a PE binary has the longPathAware manifest. Returns [true] on
    non-Windows (no check needed). Results are cached per program path. *)
val has_long_path_manifest : prog:Path.t -> bool

(** Check if the Windows LongPathsEnabled registry key is set. Respects
    [DUNE_LONG_PATH_ENABLED] env var override for testing. Cached after first
    call. Returns [true] on non-Windows. *)
val long_paths_enabled : unit -> bool

(** If any arg looks like a path exceeding [max_path]:
    - Warn once if LongPathsEnabled registry key is not set
    - Warn once per program if it lacks the longPathAware manifest *)
val check_and_warn : prog:Path.t -> dir:Path.t option -> args:string list -> unit
