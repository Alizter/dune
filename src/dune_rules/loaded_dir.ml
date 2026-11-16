open Import

type t =
  { project : Loaded_project.t
  ; source_dir : Path.Local.t
  ; output_dir : Path.Build.t
  }

let create ~project ~source_dir =
  { project; source_dir; output_dir = Loaded_project.output_path project source_dir }
;;

let project t = t.project
let source_dir t = t.source_dir
let output_dir t = t.output_dir
