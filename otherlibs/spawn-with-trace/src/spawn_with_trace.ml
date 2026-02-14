external run_internal
  :  string
  -> string array
  -> string array
  -> string option
  -> int
  -> int
  -> int
  -> Unix.process_status * string list
  = "spawn_with_trace_run_bytecode" "spawn_with_trace_run"

let run ~prog ~argv ~env ?cwd ?(stdin = Unix.stdin) ?(stdout = Unix.stdout)
    ?(stderr = Unix.stderr) () =
  let stdin_fd = (Obj.magic stdin : int) in
  let stdout_fd = (Obj.magic stdout : int) in
  let stderr_fd = (Obj.magic stderr : int) in
  run_internal prog argv env cwd stdin_fd stdout_fd stderr_fd
