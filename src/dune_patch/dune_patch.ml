open Stdune
module Re = Dune_re

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

let prefix_of_patch patch_string =
  Re.all re patch_string
  |> List.filter_map ~f:(fun group ->
    let open Option.O in
    (* A match failure means a file name couldn't be parsed. *)
    let* old_file = Re.Group.get_opt group 1 in
    let* new_file = Re.Group.get_opt group 2 in
    match old_file = "/dev/null", new_file = "/dev/null" with
    (* when both files are /dev/null we don't care about the patch. *)
    | true, true -> None
    | true, false ->
      let path = Path.Local.of_string new_file in
      let prefix =
        match Path.Local.split_first_component path with
        | Some (_, _) -> 1
        | _ -> 0
      in
      (* New file *)
      Some prefix
    | false, true ->
      (* Delete file *)
      let path = Path.Local.of_string old_file in
      let prefix =
        match Path.Local.split_first_component path with
        | Some (_, _) -> 1
        | _ -> 0
      in
      Some prefix
    | false, false ->
      let old_path = Path.Local.of_string old_file in
      let new_path = Path.Local.of_string new_file in
      let prefix =
        match
          ( Path.Local.split_first_component old_path
          , Path.Local.split_first_component new_path )
        with
        | Some (_, old_path), Some (_, new_path)
          when Path.Local.equal old_path new_path && not (Path.Local.is_root new_path) ->
          (* suffixes are the same and not empty *)
          1
        | _, _ -> 0
      in
      (* Replace file *)
      Some prefix)
  |> List.min ~f:Int.compare
  |> Option.value ~default:1
;;

let exec ~patch ~dir =
  let open Fiber.O in
  let+ () = Fiber.return () in
  let patches = patch |> Io.read_file |> fun x -> Patch.parse ~p:(prefix_of_patch x) x in
  let path p = Path.append_local dir (Path.Local.of_string p) in
    let cleanly = false in
  List.iter patches ~f:(fun patch ->
    match patch.Patch.operation with
    | Delete p | Git_ext (_, p, Patch.Delete_only) -> Path.unlink_no_err (path p)
    | Create p | Git_ext (_, p, Patch.Create_only) ->
      Patch.patch ~cleanly None patch |> Option.value_exn |> Io.write_file (path p)
    | Edit (p, q) ->
      Io.read_file (path p)
      |> fun file ->
      Patch.patch ~cleanly (Some file) patch
      |> Option.value_exn
      |> Io.write_file (path q)
    | Git_ext (_, _, Rename_only (p, q)) -> Path.rename (path p) (path q))
;;

(* CR-someday alizter: This should be an action builder. *)
module Action = Action_ext.Make (struct
    type ('path, 'target) t = 'path

    let name = "patch"
    let version = 3
    let bimap patch f _ = f patch
    let is_useful_to ~memoize = memoize
    let encode patch input _ : Sexp.t = input patch

    let action patch ~ectx:_ ~(eenv : Dune_engine.Action.env) =
      exec ~patch ~dir:eenv.working_dir
    ;;
  end)

let action ~patch = Action.action patch

module For_tests = struct
  let exec = exec
end
