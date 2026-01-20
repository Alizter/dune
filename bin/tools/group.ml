open Import

module Exec = struct
  let doc = "Command group for running wrapped tools."
  let info = Cmd.info ~doc "exec"

  (* Legacy tool-specific commands *)
  let legacy_commands =
    List.map
      [ Ocamlformat
      ; Ocamllsp
      ; Ocamlearlybird
      ; Odig
      ; Opam_publish
      ; Dune_release
      ; Ocaml_index
      ; Merlin
      ]
      ~f:Tools_common.exec_command
  ;;

  let group = Cmd.group info legacy_commands
end

module Install = struct
  let doc = "Command group for installing wrapped tools."
  let info = Cmd.info ~doc "install"

  let legacy_commands = List.map Dune_pkg.Dev_tool.all ~f:Tools_common.install_command

  let group = Cmd.group info legacy_commands
end

module Which = struct
  let doc = "Command group for printing the path to wrapped tools."
  let info = Cmd.info ~doc "which"

  let legacy_commands = List.map Dune_pkg.Dev_tool.all ~f:Tools_common.which_command

  let group = Cmd.group info legacy_commands
end

(* Generic commands for arbitrary packages - available at top level *)
module Run = struct
  let doc = "Run any opam package as a tool (locks and builds if needed)."
  let info = Cmd.info ~doc "run"
  let command = Cmd.v info Tools_common.generic_exec_term
end

module Lock = struct
  let doc = "Lock any opam package as a tool. Always re-solves dependencies."
  let info = Cmd.info ~doc "lock"
  let command = Cmd.v info Tools_common.generic_lock_term
end

module Path = struct
  let doc = "Print the path to any tool's executable."
  let info = Cmd.info ~doc "path"
  let command = Cmd.v info Tools_common.generic_which_term
end

let doc = "Command group for wrapped tools."
let info = Cmd.info ~doc "tools"

let group =
  Cmd.group
    info
    [ Exec.group
    ; Install.group
    ; Which.group
    ; Run.command      (* dune tools run <package> *)
    ; Lock.command     (* dune tools lock <package> *)
    ; Path.command     (* dune tools path <package> *)
    ; Tools_common.env_command
    ]
;;
