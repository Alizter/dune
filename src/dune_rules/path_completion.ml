open Import
open Memo.O

type t =
  { values : String.Set.t
  ; directories : directory String.Map.t
  }

and directory =
  | Opaque
  | Expandable of
      { contents : t Memo.Lazy.t
      ; nonempty : bool Memo.Lazy.t
      }

let create ~values ~directories =
  let directories =
    List.fold_left directories ~init:String.Map.empty ~f:(fun directories (name, dir) ->
      String.Map.update directories name ~f:(function
        | None | Some Opaque -> Some dir
        | Some (Expandable _ as existing) -> Some existing))
  in
  { values = String.Set.of_list values; directories }
;;

let has_candidates { values; directories } =
  if not (String.Set.is_empty values)
  then Memo.return true
  else (
    let rec loop = function
      | [] -> Memo.return false
      | (_, Opaque) :: _ -> Memo.return true
      | (_, Expandable { nonempty; _ }) :: directories ->
        Memo.Lazy.force nonempty
        >>= (function
         | true -> Memo.return true
         | false -> loop directories)
    in
    loop (String.Map.to_list directories))
;;

let opaque = Opaque

let expandable contents =
  let nonempty =
    Memo.lazy_ ~name:"path-completion-nonempty" (fun () ->
      let* contents = Memo.Lazy.force contents in
      has_candidates contents)
  in
  Expandable { contents; nonempty }
;;

type candidate =
  | Value of string
  | Directory of string * directory

let matching_candidates { values; directories } ~prefix =
  let matches name = String.starts_with name ~prefix in
  let values =
    String.Set.to_list values
    |> List.filter_map ~f:(fun name -> Option.some_if (matches name) (Value name))
  in
  let+ directories =
    String.Map.to_list directories
    |> Memo.parallel_map ~f:(fun (name, dir) ->
      if not (matches name)
      then Memo.return None
      else (
        match dir with
        | Opaque -> Memo.return (Some (Directory (name, dir)))
        | Expandable { nonempty; _ } ->
          let+ nonempty = Memo.Lazy.force nonempty in
          Option.some_if nonempty (Directory (name, dir))))
  in
  values @ List.filter_opt directories
;;

let all_candidates t = matching_candidates t ~prefix:""

let rec find t = function
  | [] -> Memo.return (Some t)
  | component :: components ->
    (match String.Map.find t.directories (Filename.to_string component) with
     | None | Some Opaque -> Memo.return None
     | Some (Expandable { contents; _ }) ->
       let* child = Memo.Lazy.force contents in
       find child components)
;;

let rec expand_directory path = function
  | Opaque -> Memo.return (path ^ "/")
  | Expandable { contents; _ } ->
    let* child = Memo.Lazy.force contents in
    let* candidates = all_candidates child in
    (match candidates with
     | [ Value name ] -> Memo.return (path ^ "/" ^ name)
     | [ Directory (name, dir) ] -> expand_directory (path ^ "/" ^ name) dir
     | [] | _ :: _ :: _ -> Memo.return (path ^ "/"))
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
  let* parent = find t (Path.Source.explode parent_dir) in
  match parent with
  | None -> Memo.return []
  | Some parent ->
    let* candidates = matching_candidates parent ~prefix in
    let+ candidates =
      Memo.parallel_map candidates ~f:(function
        | Value name -> Memo.return (with_parent name)
        | Directory (name, dir) -> expand_directory (with_parent name) dir)
    in
    String.Set.of_list candidates |> String.Set.to_list
;;
