(** Fine-grained OCaml compilation cache.

    This module provides a secondary cache layer for OCaml compilation that uses
    fine-grained dependencies (from ocamlobjinfo) rather than coarse library-level
    dependencies. This enables better cache hit rates when changes to a library
    don't affect all modules that depend on it.

    The workflow is:
    1. Before compilation, check if we have cached ocamlobjinfo data for this
       source+flags combination (via [Fine_grained_deps])
    2. If yes, compute a fine-grained key using [compute_fine_key] with only
       the actually-imported .cmi digests
    3. Try [lookup] with the fine key to restore cached artifacts
    4. If miss, compile normally, then run ocamlobjinfo and [store] the results

    The configuration flag [Dune_config.fine_grained_ocaml_cache] controls
    whether this feature is enabled. *)

open Import

(** Configuration for reproducibility checks on cache hits. *)
module Reproducibility_check : sig
  type t =
    | Skip (** Never verify cache hits *)
    | Check_with_probability of float (** Verify with given probability *)
    | Check (** Always verify cache hits *)

  val sample : t -> bool
end

(** Current reproducibility check setting. Controlled by DUNE_FINE_CACHE_CHECK env var:
    - "1" or "true": always check
    - "0.1": check with 10% probability
    - unset: skip checks *)
val reproducibility_check : Reproducibility_check.t ref

(** Compute a fine-grained cache key from source, compiler, flags, and actual dependencies.

    The key is computed from:
    - source_digest: the content of the source file
    - ocaml_digest: digest of the OCaml compiler being used
    - flags_digest: the compiler flags
    - imported_cmi_digests: digests of only the actually-imported .cmi files
      (as determined by ocamlobjinfo output)
    - cm_kind: the compilation kind (cmo, cmx, etc.) to separate byte/native caches *)
val compute_fine_key
  :  source_digest:Digest.t
  -> ocaml_digest:Digest.t
  -> flags_digest:Digest.t
  -> imported_cmi_digests:Digest.t Module_name.Unique.Map.t
  -> cm_kind:string
  -> Digest.t

(** Look up artifacts in the fine-grained cache and restore them.

    Returns [true] if the cache contains the required target for the given fine
    key and it was successfully restored. Optional targets are restored if
    available but don't affect the return value. Returns [false] if the required
    target is not found or restoration failed.

    The required_target is typically the primary .cmo/.cmx file. Optional targets
    include .cmt, .cmi, etc. that may not always be produced for all compilation
    modes (e.g., .cmt isn't always produced for native compilation). *)
val lookup_and_restore
  :  mode:Dune_cache_storage.Mode.t
  -> fine_key:Digest.t
  -> required_target:Path.Build.t
  -> optional_targets:Path.Build.t list
  -> bool

(** Store artifacts with a fine-grained key after compilation.

    This is called after successful compilation to store the produced artifacts
    using the fine-grained key for future lookups. [targets] is the list of
    produced files (e.g., .cmo, .cmi). *)
val store
  :  mode:Dune_cache_storage.Mode.t
  -> fine_key:Digest.t
  -> targets:Path.Build.t list
  -> unit
