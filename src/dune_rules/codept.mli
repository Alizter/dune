(** Module dependency discovery using codept.

    Runs codept's [-m2l] mode on a source file, parses the M2L AST to extract
    referenced compilation units, resolves them to [.cmi]/[.cmx] paths (both
    local modules and cross-library), and produces both the dynamic path
    dependencies and the [-I] flags needed for compilation.

    This replaces both [other_cm_files] (dep graph) and [Includes] (library
    [-I] flags + Hidden_deps) when codept is enabled. *)

open Import

(** [cm_deps cctx ~ml_kind ~cm_kind m] returns [Command.Args.t] that:
    - registers all [.cmi]/[.cmx] paths needed to compile module [m] as
      dynamic path dependencies
    - produces the [-I] flags pointing to the directories containing those
      files

    This is a drop-in replacement for both [other_cm_files] and the library
    [Includes] in [Module_compilation.build_cm]. *)
val cm_deps
  :  Compilation_context.t
  -> ml_kind:Ml_kind.t
  -> cm_kind:Lib_mode.Cm_kind.t
  -> Module.t
  -> Command.Args.without_targets Command.Args.t
