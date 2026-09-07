open Import

(** Complete tests and directories relative to [cwd]. Unambiguous directory
    chains are completed in full. *)
val candidates : cwd:Path.Source.t -> token:string -> string list Memo.t
