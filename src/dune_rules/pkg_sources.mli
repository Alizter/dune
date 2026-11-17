open Import
module Backing = Source_tree.Rules.Backing

val package_of_artifact_path : Path.Build.t -> Package.Name.t option

(** The same question for a directory named by its place in a context. *)
val package_of_dir_in_context : Path.Local.t -> Package.Name.t option

(** Where the source of a build path of a context is: the workspace, or the
    path itself inside a mounted package. *)
val source_location : Path.Build.t -> Path.t

module Source_input : sig
  type t =
    { files : (Path.t * Path.Local.t) list
    ; directories : Path.Local.t list
    }
end

module Candidate : sig
  type t

  val name : t -> Package.Name.t
  val lock_pkg : t -> Dune_pkg.Lock_dir.Pkg.t
  val source_loc : t -> Loc.t
  val files_dir : t -> Path.Build.t
  val artifact_root : t -> Path.Build.t
  val dependencies : t -> Package.Name.Set.t Memo.t

  (** Root of the package's opaque build and install directories. *)
end

val candidates : Context_name.t -> Candidate.t list Memo.t
val find_candidate : Context_name.t -> Package.Name.t -> Candidate.t option Memo.t
val source : Candidate.t -> Source_input.t Memo.t

(** Every source file and directory under a package backing. *)
val listing : loc:Loc.t -> Backing.t -> Source_input.t Memo.t

module Mounted : sig
  type t

  val candidate : t -> Candidate.t
  val tree : t -> Source_tree.Rules.Mounted.t option
  val projects : t -> (Dune_project.t * Source_tree.Rules.Dir.t) list
  val kind : t -> ([ `Dune | `Opam ], User_message.t list) result
  val kind_exn : t -> [ `Dune | `Opam ] Memo.t
end

(** A package's mounted source, prepared on demand: [None] when the package
    is not locked. *)
val find_mounted : Context_name.t -> Package.Name.t -> Mounted.t option Memo.t

val find_mounted_kind
  :  Context_name.t
  -> Package.Name.t
  -> (Mounted.t * [ `Dune | `Opam ]) option Memo.t

(** How a package's source reaches its mount. *)
module Preparation : sig
  type t =
    | Opaque (** The package has no source to mount. *)
    | Plain of
        { dir : Backing.t
        ; native : bool
        } (** The external or fetched directory is used as it is. *)
    | Prepared of
        { patches : (Loc.t * Path.Local.t) list
        ; rest : Dune_lang.Action.t list
        ; native : bool
        }
    (** [prepared_source] holds the fetched source with the package's lock
        directory files and extra sources added, then [patches] applied.
        [rest] is what remains of the build action after those patches.
        [native] is false when [rest] still transforms the source, so a dune
        project found in it cannot be loaded before the recipe has run. *)
end

val preparation : Context_name.t -> Package.Name.t -> Preparation.t option Memo.t

(** The directory a package's mount copies its source from, when its source is
    mounted. *)
val mount_backing : Context_name.t -> Package.Name.t -> Backing.t option Memo.t

(** A private copy of a mounted package's source, with its leading patches
    applied. Programs that run in the source, such as dune files in OCaml syntax,
    run there and not in the fetched source, which is shared between packages. *)
val prepared_source : Context_name.t -> Package.Name.t -> Path.Build.t
