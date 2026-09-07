open Import
open Memo.O

type t =
  { values : String.Set.t
  ; directories : directory String.Map.t
  }

and directory =
  | Opaque
  | Expandable of t Memo.Lazy.t

let opaque = Opaque
let expandable contents = Expandable contents

let create ~values ~directories =
  let directories =
    List.fold_left directories ~init:String.Map.empty ~f:(fun directories (name, dir) ->
      String.Map.update directories name ~f:(function
        | None | Some Opaque -> Some dir
        | Some (Expandable _ as existing) -> Some existing))
  in
  { values = String.Set.of_list values; directories }
;;

let rec find t = function
  | [] -> Memo.return (Some t)
  | component :: components ->
    (match String.Map.find t.directories (Filename.to_string component) with
     | None | Some Opaque -> Memo.return None
     | Some (Expandable child) ->
       let* child = Memo.Lazy.force child in
       find child components)
;;

let split_token ~cwd token =
  match String.rindex_opt token '/' with
  | None -> cwd, "", token
  | Some i ->
    let parent_string = String.sub token ~pos:0 ~len:i in
    let prefix = String.sub token ~pos:(i + 1) ~len:(String.length token - i - 1) in
    let parent =
      if String.is_empty parent_string
      then cwd
      else Path.Source.relative cwd parent_string
    in
    parent, parent_string, prefix
;;

let candidates t ~cwd ~token =
  let parent_dir, parent_string, prefix = split_token ~cwd token in
  let with_parent basename =
    if String.is_empty parent_string then basename else parent_string ^ "/" ^ basename
  in
  let matches name = String.starts_with name ~prefix in
  let* parent = find t (Path.Source.explode parent_dir) in
  match parent with
  | None -> Memo.return []
  | Some { values; directories } ->
    let values =
      String.Set.to_list values
      |> List.filter_map ~f:(fun name -> Option.some_if (matches name) (with_parent name))
    in
    let directories =
      String.Map.keys directories
      |> List.filter_map ~f:(fun name ->
        Option.some_if (matches name) (with_parent (name ^ "/")))
    in
    values @ directories |> String.Set.of_list |> String.Set.to_list |> Memo.return
;;
