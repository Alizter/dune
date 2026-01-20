open Import

(** Configuration for a tool from the (tool ...) stanza in dune-workspace.

    The package field uses the same dependency syntax as (depends ...):
    - Just package name: ocamlformat
    - With version constraint: (ocamlformat (= 0.26.2))

    Syntax examples:
    {v
    ;; Simple - just package name
    (tool (package ocamlformat))

    ;; With version constraint
    (tool (package (ocamlformat (= 0.26.2))))

    ;; With additional options
    (tool
      (package (ocamlformat (= 0.26.2)))
      (executable ocamlformat-rpc)
      (compiler_compatible))
    v}
*)
type t =
  { package : Package.Name.t (** Opam package name *)
  ; version : Package_constraint.t option (** Optional version constraint *)
  ; executable : string option (** Optional: exe name, defaults to package name *)
  ; compiler_compatible : bool (** Whether tool must match project compiler *)
  ; loc : Loc.t
  }

val to_dyn : t -> Dyn.t
val equal : t -> t -> bool
val hash : t -> int

(** The opam package name for this tool *)
val package_name : t -> Package.Name.t

(** The executable name (defaults to package name if not specified) *)
val exe_name : t -> string

(** Whether the tool needs to be built with the same compiler as the project *)
val needs_matching_compiler : t -> bool

(** The version constraint for this tool, if specified *)
val version_constraint : t -> Package_constraint.t option

(** Decoder for the (tool ...) stanza *)
val decode : t Dune_lang.Decoder.t

(** Encoder for serialization *)
val encode : t -> Dune_lang.t list
