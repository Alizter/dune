(** Module dependency discovery using codept.

    Runs codept's [-m2l] mode on a source file, parses the M2L AST to extract
    referenced compilation units, resolves them to [.cmi]/[.cmx] paths (both
    local modules and cross-library), and returns those paths as dynamic
    dependencies for the compilation rule.

    This replaces both the dep graph ([Dep_graph.deps_of] + [other_cm_files])
    and the library include deps ([Lib_file_deps]) when codept is enabled. *)

open Import

(** [cm_deps cctx ~ml_kind ~cm_kind m] returns an action builder that
    registers all [.cmi]/[.cmx] paths needed to compile module [m] as
    dynamic path dependencies. This is a drop-in replacement for the
    [other_cm_files] computation in [Module_compilation.build_cm]. *)
val cm_deps
  :  Compilation_context.t
  -> ml_kind:Ml_kind.t
  -> cm_kind:Lib_mode.Cm_kind.t
  -> Module.t
  -> unit Action_builder.t
