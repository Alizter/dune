open Import

(** Must be called during initialization to wire up install entry resolution. *)
val set_entry_resolver
  :  (Super_context.t -> Package.Name.t -> Install.Entry.Sourced.Unexpanded.t list Memo.t)
  -> unit

(** Compute the list of files that would be in the layout for a set of
    packages. Used by consumers to set up file-level dependencies. *)
val layout_files : Super_context.t -> Package.Name.t list -> Path.t list Memo.t

(** The [lib] subdirectory of the layout for a set of packages. Suitable for
    adding to [OCAMLPATH]. *)
val layout_lib_root : Super_context.t -> Package.Name.t list -> Path.Build.t

(** Generate symlink rules for the layout directory identified by [key].
    Called from [gen_rules] when the build system visits
    [.install-layout/<key>/]. *)
val gen_rules : Super_context.t -> dir:Path.Build.t -> string -> unit Memo.t
