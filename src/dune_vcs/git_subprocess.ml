open Stdune
open Fiber.O
module Process = Dune_engine.Process

type t = { root : Path.t }

let create ~root = { root }

let env =
  Env.add Env.initial ~var:"LC_ALL" ~value:"C"
  |> Env.add ~var:"GIT_TERMINAL_PROMPT" ~value:"0"
;;

let git () =
  Vcs.git_for ~needed_for:"to read a local git repository at a specific revision"
;;

let rev_parse_single { root } rev =
  let git = git () in
  let+ lines, code =
    Process.run_capture_lines
      ~dir:root
      ~display:Quiet
      ~env
      Return
      git
      [ "rev-parse"; "--verify"; "--quiet"; sprintf "%s^{commit}" rev ]
  in
  match lines, code with
  | [ line ], 0 -> Some (String.trim line)
  | _ -> None
;;

let rev_list { root } rev_arg =
  let git = git () in
  let+ lines, code =
    Process.run_capture_lines
      ~dir:root
      ~display:Quiet
      ~env
      Return
      git
      [ "rev-list"; "--reverse"; rev_arg ]
  in
  if code = 0 then Some (List.map lines ~f:String.trim) else None
;;

(* Parse a single line of [git ls-tree -r <commit>] output of the form:
     <perm> SP <type> SP <sha> TAB <path>
   We only keep blobs; submodules (commit type) are reported as empty
   directories higher up. *)
let parse_ls_tree_line line =
  match String.lsplit2 line ~on:'\t' with
  | None -> None
  | Some (header, path) ->
    let fields = String.split header ~on:' ' in
    (match List.filter fields ~f:(fun s -> not (String.is_empty s)) with
     | [ _perm; "blob"; sha ] -> Some (Path.Local.of_string path, sha)
     | _ -> None)
;;

let ls_tree_recursive { root } ~commit =
  let git = git () in
  let+ lines, code =
    Process.run_capture_lines
      ~dir:root
      ~display:Quiet
      ~env
      Return
      git
      [ "ls-tree"; "-r"; commit ]
  in
  if code <> 0
  then
    User_error.raise [ Pp.textf "git ls-tree failed for commit %s (exit %d)" commit code ];
  List.filter_map lines ~f:parse_ls_tree_line
;;

let cat_file_blob { root } ~commit ~path =
  let git = git () in
  let arg = sprintf "%s:%s" commit (Path.Local.to_string path) in
  let+ out, code =
    Process.run_capture
      ~dir:root
      ~display:Quiet
      ~env
      Return
      git
      [ "cat-file"; "blob"; arg ]
  in
  if code <> 0
  then
    User_error.raise
      [ Pp.textf
          "git cat-file failed for %s:%s (exit %d)"
          commit
          (Path.Local.to_string path)
          code
      ];
  out
;;
