(** Parse ocamlobjinfo output *)

open Import

type t = Module_name.Unique.Set.t Ml_kind.Dict.t

val to_dyn : t -> Dyn.t

val rules
  :  Ocaml_toolchain.t
  -> dir:Path.Build.t
  -> sandbox:Sandbox_config.t option
  -> units:Path.t list
  -> t list Action_builder.t

(** Like [rules] but also captures the interface digests (CMI CRCs) from ocamlobjinfo output *)
type with_interface_digests = (Module_name.Unique.t * string) list Ml_kind.Dict.t

val rules_with_interface_digests
  :  Ocaml_toolchain.t
  -> dir:Path.Build.t
  -> sandbox:Sandbox_config.t option
  -> units:Path.t list
  -> with_interface_digests list Action_builder.t

(** Run ocamlobjinfo on an archive to extract module names defined in it *)
val archive_rules
  :  Ocaml_toolchain.t
  -> dir:Path.Build.t
  -> sandbox:Sandbox_config.t option
  -> archive:Path.t
  -> Module_name.Unique.Set.t Action_builder.t

(** For testing only *)
val parse : string -> t list

(** Parse ocamlobjinfo output with interface digests *)
val parse_with_interface_digests : string -> with_interface_digests list

(** Parse archive output to extract module names defined in the archive *)
val parse_archive : string -> Module_name.Unique.Set.t
