open Import

val gen_rules_for_lib
  :  Super_context.t
  -> Compilation_context.t
  -> Library.t
  -> dir:Path.Build.t
  -> unit Memo.t

val gen_rules_for_exe
  :  Super_context.t
  -> Compilation_context.t
  -> Executables.t
  -> dir:Path.Build.t
  -> unit Memo.t
