open Import

(** This module provides support for the [ocaml-uideps] indexing tool. Its role
    is to index every value in the project by their definition in order for
    language server to be able to fetch project-wide occurrences.

    Indexing all definitions usages is a two step process:

    - first, for all compilation contexts we generate the uideps for all the
      modules in that cctx in the corresponding obj_dir.
    - then we aggregate all these separate indexes into a unique one. *)

(** [cctx_rules ~entry_modules cctx] sets the rules needed to generate the
    indexes for every module in the compilation context [cctx] and aggregate
    them in a [cctx.uideps] index covering the whole compilation context.

    For executables, [entry_modules] should be the main modules of each
    executable in the stanza. Only modules reachable from these entry points
    will be indexed, avoiding compilation errors when overlapping executables
    have different library dependencies (see issue #13566).

    For libraries and melange, [entry_modules] should be empty to index all
    user-written modules. *)
val cctx_rules : entry_modules:Module.t list -> Compilation_context.t -> unit Memo.t

(** [context_indexes] lists all the available cctx.ocaml-index files in the
    given context *)
val context_indexes : Context.t -> Path.t list Action_builder.t

(** [project_rule] adds a rule that will aggregate all the generated indexes
    into one global, project-wide, index *)
val project_rule : Super_context.t -> Dune_project.t -> unit Memo.t
