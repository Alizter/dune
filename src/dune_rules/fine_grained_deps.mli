(** Fine-grained OCaml module dependency storage.

    This module stores ocamlobjinfo results (which modules a compilation unit
    actually imports) keyed by (source_digest, ocaml_digest, flags_digest).
    This enables fine-grained cache lookups that only depend on actually-imported
    modules rather than all modules in dependent libraries.

    Usage:
    1. After compiling a module, run [Ocamlobjinfo.rules] to get the imports
    2. Convert the result to a [value] and store with [store]
    3. On subsequent builds, use [restore] to get cached imports
    4. Use the imports with [Fine_grained_cache.compute_fine_key] for lookups

    The configuration flag [Dune_config.fine_grained_ocaml_cache] controls
    whether this feature is enabled. *)

open Import

(** Key for looking up fine-grained dependencies. *)
type key =
  { source_digest : Digest.t (** Digest of the source file (.ml or .mli) *)
  ; ocaml_digest : Digest.t (** Digest of the OCaml compiler being used *)
  ; flags_digest : Digest.t (** Digest of the compiler flags affecting the compilation *)
  }

(** The fine-grained dependency information extracted from ocamlobjinfo. *)
type value =
  { imported_intf : Module_name.Unique.Set.t
    (** Interface modules imported (from "Interfaces imported:" section) *)
  ; imported_impl : Module_name.Unique.Set.t
    (** Implementation modules imported (from "Implementations imported:" section) *)
  }

(** Store ocamlobjinfo results for future fine-grained cache lookups. *)
val store
  :  mode:Dune_cache_storage.Mode.t
  -> key:key
  -> value:value
  -> Dune_cache_storage.Store_result.t

(** Restore ocamlobjinfo results for a given source+flags combination. *)
val restore : key:key -> value Dune_cache_storage.Restore_result.t
