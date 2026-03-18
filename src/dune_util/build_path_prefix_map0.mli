open Stdune

(** The [BUILD_PATH_PREFIX_MAP] variable *)
val _BUILD_PATH_PREFIX_MAP : Env.Var.t

(** [extend_build_path_prefix_map env how map] extends the path rewriting rules
    encoded in the [BUILD_PATH_PREFIX_MAP] variable.

    Note that the rewriting rules are applied from right to left, so the last
    rule of [map] will be tried first.

    If the environment variable is already defined in [env], [how] explains
    whether the rules in [map] should be tried before or after the existing
    ones. *)
val extend_build_path_prefix_map
  :  Env.t
  -> [ `Existing_rules_have_precedence | `New_rules_have_precedence ]
  -> Build_path_prefix_map.map
  -> Env.t

(** On Windows, return extra prefix-map entries that match the backslash
    and cygwin/MSYS2 forms of [source], all mapped to [target]. Returns
    [[]] on non-Windows or when [source] is not a drive-letter rooted
    path. *)
val win32_extra_entries : source:string -> target:string -> Build_path_prefix_map.map
