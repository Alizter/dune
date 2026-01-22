open Import

let version_of_ocamlformat_config ocamlformat_config =
  Io.lines_of_file ocamlformat_config
  |> List.find_map ~f:(fun line ->
    match String.split_on_char ~sep:'=' line |> List.map ~f:String.trim with
    | [ "version"; value ] -> Some (Package_version.of_string value)
    | _ -> None)
;;

let version_of_current_project's_ocamlformat_config () =
  let ocamlformat_config = Path.Source.of_string ".ocamlformat" |> Path.source in
  match Path.exists ocamlformat_config with
  | false -> None
  | true -> version_of_ocamlformat_config ocamlformat_config
;;

(** Find the .ocamlformat file that applies to a given source directory.
    Searches upward from the directory until it finds one or reaches root. *)
let find_ocamlformat_config_for_dir dir =
  let rec search dir =
    let config = Path.Source.relative dir ".ocamlformat" in
    let config_path = Path.source config in
    if Path.exists config_path
    then Some config_path
    else
      match Path.Source.parent dir with
      | None -> None
      | Some parent -> search parent
  in
  search dir
;;

(** Get the version from the .ocamlformat file that applies to a source directory *)
let version_for_dir dir =
  match find_ocamlformat_config_for_dir dir with
  | None -> None
  | Some config_path -> version_of_ocamlformat_config config_path
;;
