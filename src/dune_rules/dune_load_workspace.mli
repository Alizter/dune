(** Workspace source discovery, independent of build contexts and mounted projects. *)

open Import

type t =
  { dune_files :
      (Source_tree.Rules.Dir.t * Dune_project.t * Source.Dune_file.t) Appendable_list.t
  ; packages : Package.t Package.Name.Map.t
  ; projects : (Dune_project.t * Source_tree.Rules.Dir.t) list
  ; mask : Only_packages.t
  }

val load : unit -> t Memo.t

(** Evaluate package availability without constructing a build context. *)
val package_enabled : Package.t -> bool Memo.t
