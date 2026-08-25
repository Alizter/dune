open Import

val make : Context_name.t -> Context_name.t
val resolver : Context_name.t -> Context_name.t option
val resolver_or_self : Context_name.t -> Context_name.t
