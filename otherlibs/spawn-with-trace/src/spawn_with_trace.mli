(** Spawn a process with syscall tracing using seccomp-bpf + ptrace.

    This library spawns a child process and traces all openat syscalls,
    collecting the file paths that the process attempts to open. *)

(** [run ~prog ~argv ~env ?cwd ?stdin ?stdout ?stderr ()] spawns the program
    [prog] with arguments [argv] and environment [env], optionally in directory
    [cwd]. The optional [stdin], [stdout], [stderr] parameters allow redirecting
    the child's standard file descriptors.

    Returns [(status, paths)] where:
    - [status] is the process exit status
    - [paths] is the list of file paths that the process attempted to open

    @raise Unix.Unix_error if fork or tracing fails
    @raise Unix.Unix_error with ENOTSUP on unsupported platforms *)
val run
  :  prog:string
  -> argv:string array
  -> env:string array
  -> ?cwd:string
  -> ?stdin:Unix.file_descr
  -> ?stdout:Unix.file_descr
  -> ?stderr:Unix.file_descr
  -> unit
  -> Unix.process_status * string list
