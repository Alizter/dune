(** Cache wrapper action extension for fine-grained OCaml compilation caching.

    This action wraps a compilation command and checks the fine-grained cache
    before execution. On cache hit, it restores the artifacts. On cache miss,
    it executes the wrapped action. *)

open Import

val wrap
  :  wrapped_action:Action.t
  -> source_digest:Digest.t
  -> ocaml_digest:Digest.t
  -> flags_digest:Digest.t
  -> fine_deps_key:Digest.t
  -> targets:Path.Build.t list
  -> module_name:string
  -> cm_kind_str:string
  -> cm_file:Path.Build.t
  -> ocamlobjinfo_path:Path.t
  -> obj_dir:Path.Build.t
  -> dep_obj_dirs:Path.Build.t list
  -> Action.t
