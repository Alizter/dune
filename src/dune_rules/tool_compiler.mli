open Import

(** Compiler detection for tools.

    This module detects how the project gets its compiler and generates
    appropriate constraints for tool solving. The key insight is that
    tools should use the same compiler as the project:
    - If from pkg management, match that pkg's compiler
    - If from system, use system-ocaml
*)

(** The source of the compiler for the project *)
type compiler_source =
  | From_pkg of
      { name : Package.Name.t
      ; version : Package_version.t
      }
  | From_system of { version : string }
  | From_opam_switch of { prefix : string }
  | Unknown

val to_dyn : compiler_source -> Dyn.t

(** Detect the compiler source for the default context.
    Priority: lock dir > opam switch > system *)
val detect : unit -> compiler_source Memo.t

(** Generate package dependencies for tool solving based on compiler source.
    This ensures tools are built with a compatible compiler. *)
val constraints_for_tool : compiler_source -> Package_dependency.t list

(** Get compiler constraints for a tool, detecting the compiler source first.
    Convenience function combining [detect] and [constraints_for_tool]. *)
val get_constraints : unit -> Package_dependency.t list Memo.t
