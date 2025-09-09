open Stdune

let re =
  let line xs = Re.seq ((Re.bol :: xs) @ [ Re.eol ]) in
  let followed_by_line xs = Re.seq [ Re.str "\n"; line xs ] in
  let filename = Re.group (Re.rep1 (Re.compl [ Re.space ])) in
  (* We don't care about what's after the filename. (likely a timestamp) *)
  let junk = Re.rep Re.notnl in
  Re.compile
  @@ Re.seq
       [ line [ Re.str {|--- |}; filename; junk ]
       ; followed_by_line [ Re.str {|+++ |}; filename; junk ]
       ]
;;

let prefix_of_patch ~loc patch_string =
  Re.all re patch_string
  |> List.filter_map ~f:(fun group ->
    let open Option.O in
    (* A match failure means a file name couldn't be parsed. *)
    let* old_file = Re.Group.get_opt group 1 in
    let* new_file = Re.Group.get_opt group 2 in
    let validate_as_path file =
      if not (Filename.is_relative file)
      then
        User_error.raise
          ~loc
          [ Pp.textf "Absolute path %S in patch file is not allowed." file ]
      else (
        let path =
          match Path.Local.parse_string_exn ~loc file with
          | exception User_error.E _ ->
            User_error.raise
              ~loc
              [ Pp.textf
                  "Patch files may not reference paths starting with \"..\" as they \
                   would access files outside the project."
              ]
          | path -> path
        in
        if
          Path.Local.is_root path
          (* TODO: location is not quite correct here. Should instead
             be location of patch file. *)
        then
          User_error.raise ~loc [ Pp.textf "Directory %S in patch file is invalid." file ];
        path)
    in
    let prefix file =
      match validate_as_path file |> Path.Local.split_first_component with
      | Some _ -> 1
      | None -> 0
    in
    match old_file = "/dev/null", new_file = "/dev/null" with
    (* when both files are /dev/null we don't care about the patch. *)
    | true, true -> None
    | true, false ->
      (* Create file *)
      Some (prefix new_file)
    | false, true ->
      (* Delete file *)
      Some (prefix old_file)
    | false, false ->
      let old_path = validate_as_path old_file in
      let new_path = validate_as_path new_file in
      let prefix =
        match
          ( Path.Local.split_first_component old_path
          , Path.Local.split_first_component new_path )
        with
        | Some (_, old_suffix), Some (_, new_suffix)
          when not (Path.Local.is_root old_suffix) && not (Path.Local.is_root new_suffix) ->
          (* Both files have prefixes and suffixes are not empty *)
          1
        | _, _ -> 0
      in
      (* Replace file *)
      Some prefix)
  |> List.min ~f:Int.compare
  |> Option.value ~default:0
;;

let parse_patches ~loc patch_contents =
  Patch.parse ~p:(prefix_of_patch ~loc patch_contents) patch_contents
;;

let apply_patches ~dir patches =
  let path p = Path.append_local dir (Path.Local.of_string p) in
  let cleanly = true in
  List.iter patches ~f:(fun patch ->
    match patch.Patch.operation with
    | Delete p | Git_ext (_, p, Patch.Delete_only) -> Path.unlink_no_err (path p)
    | Create p | Git_ext (_, p, Patch.Create_only) ->
      Patch.patch ~cleanly None patch |> Option.value_exn |> Io.write_file (path p)
    | Edit (p, q) ->
      let source_path = path p in
      if Path.exists source_path
      then
        Io.read_file source_path
        |> fun file ->
        Patch.patch ~cleanly (Some file) patch
        |> Option.value_exn
        |> Io.write_file (path q)
      else User_error.raise [ Pp.textf "Cannot edit file %S: file does not exist" p ]
    | Git_ext (mine, their, Rename_only (_, _)) -> Path.rename (path mine) (path their))
;;

let exec ~loc ~dir ~patch =
  let open Fiber.O in
  let+ () = Fiber.return () in
  Io.read_file patch |> parse_patches ~loc |> apply_patches ~dir
;;

(* CR-someday alizter: This should be an action builder. *)
module Action = Action_ext.Make (struct
    open Dune_engine

    type ('path, 'target) t = 'path

    let name = "patch"
    let version = 3
    let bimap patch f _ = f patch
    let is_useful_to ~memoize = memoize
    let encode patch input _ : Sexp.t = input patch

    let action patch ~(ectx : Action.context) ~(eenv : Action.env) =
      exec ~loc:ectx.rule_loc ~dir:eenv.working_dir ~patch
    ;;
  end)

let action ~patch = Action.action patch

module For_tests = struct
  module Patch = Patch

  let prefix_of_patch = prefix_of_patch
  let parse_patches = parse_patches
  let apply_patches = apply_patches
  let exec = exec
end
