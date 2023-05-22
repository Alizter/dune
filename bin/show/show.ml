open Import

let doc = "Command group for showing information about the workspace"

let group =
  Cmd.group (Cmd.info ~doc "show") [ Targets_cmd.command; Aliases_cmd.command ]
