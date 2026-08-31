open Import

type t

val make : loc:Loc.t -> packages:Package_name.Set.t -> t
val loc : t -> Loc.t
val packages : t -> Package_name.Set.t
val decode : t Decoder.t
