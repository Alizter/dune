open Import

(** Complete tests and immediate subdirectories relative to [cwd]. *)
val candidates : cwd:Path.Source.t -> token:string -> string list Memo.t
