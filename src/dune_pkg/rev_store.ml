open Stdune
open Dune_vcs
module Process = Dune_engine.Process
module Display = Dune_engine.Display
module Re = Dune_re
open Fiber.O

type t =
  { dir : Path.t
  ; lock : Fiber.Mutex.t
  }

type rev = Rev of string

let equal { dir; lock = _ } t = Path.equal dir t.dir
let display = Display.Quiet
let failure_mode = Process.Failure_mode.Strict
let output_limit = Sys.max_string_length
let make_stdout () = Process.Io.make_stdout ~output_on_success:Swallow ~output_limit
let make_stderr () = Process.Io.make_stderr ~output_on_success:Swallow ~output_limit

let run { dir; lock = _ } =
  let stdout_to = make_stdout () in
  let stderr_to = make_stderr () in
  let git = Lazy.force Vcs.git in
  Process.run ~dir ~display ~stdout_to ~stderr_to failure_mode git
;;

let run_capture_line { dir; lock = _ } =
  let git = Lazy.force Vcs.git in
  Process.run_capture_line ~dir ~display failure_mode git
;;

let run_capture_lines { dir; lock = _ } =
  let git = Lazy.force Vcs.git in
  Process.run_capture_lines ~dir ~display failure_mode git
;;

let run_capture_zero_separated_lines { dir; lock = _ } =
  let git = Lazy.force Vcs.git in
  Process.run_capture_zero_separated ~dir ~display failure_mode git
;;

let show { dir; lock = _ } (Rev rev) path =
  let git = Lazy.force Vcs.git in
  let failure_mode = Vcs.git_accept () in
  let command = [ "show"; sprintf "%s:%s" rev (Path.Local.to_string path) ] in
  let stderr_to = make_stderr () in
  Process.run_capture ~dir ~display ~stderr_to failure_mode git command
  >>| Result.to_option
;;

let create ~dir =
  let t = { dir; lock = Fiber.Mutex.create () } in
  let* () = Fiber.return () in
  let+ () =
    match Fpath.mkdir_p (Path.to_string dir) with
    | Already_exists -> Fiber.return ()
    | Created -> run t [ "init"; "--bare" ]
    | Already_exists_not_directory dir ->
      User_error.raise
        [ Pp.textf "%s isn't a directory" dir ]
        ~hints:[ Pp.text "delete this file or check its permissions" ]
  in
  t
;;

module Remote = struct
  type nonrec t =
    { repo : t
    ; handle : string
    ; mutable default_branch : string option
    }

  let default_branch t = t.default_branch
  let head_branch = Re.(compile (seq [ str "HEAD branch: "; group (rep1 any); eol ]))

  let update ({ repo; handle; _ } as t) =
    let* () = run repo [ "fetch"; handle; "--no-tags" ] in
    let+ default_branch =
      run_capture_lines repo [ "remote"; "show"; handle ]
      >>| List.find_map ~f:(fun line ->
        Re.exec_opt head_branch line
        |> Option.map ~f:(fun groups -> Re.Group.get groups 1))
    in
    t.default_branch <- default_branch
  ;;

  let equal { repo; handle; _ } t = equal repo t.repo && String.equal handle t.handle

  module At_rev = struct
    type nonrec t =
      { remote : t
      ; revision : rev
      }

    let content { remote; revision } path = show remote.repo revision path

    let directory_entries { remote; revision = Rev rev } path =
      (* TODO: there are much better of implementing this:
         1. Using one [$ git show] for the entire director
         2. using libgit or ocamlgit
         3. using [$ git archive] *)
      let+ all_files =
        run_capture_zero_separated_lines
          remote.repo
          [ "ls-tree"; "-z"; "--name-only"; "-r"; rev ]
      in
      List.filter_map all_files ~f:(fun entry ->
        let path_entry = Path.Local.of_string entry in
        Option.some_if (Path.Local.is_descendant path_entry ~of_:path) path_entry)
    ;;

    let equal { remote; revision = Rev revision } t =
      let (Rev revision') = t.revision in
      equal remote t.remote && String.equal revision revision'
    ;;

    let repository_id { revision = Rev rev; remote = _ } = Repository_id.of_git_hash rev
  end

  let rev_of_name remote ~name =
    (* TODO handle non-existing name *)
    let+ rev =
      run_capture_line remote.repo [ "rev-parse"; sprintf "%s/%s" remote.handle name ]
    in
    Some { At_rev.remote; revision = Rev rev }
  ;;

  let rev_of_repository_id ({ repo; _ } as remote) repo_id =
    match Repository_id.git_hash repo_id with
    | None -> Fiber.return None
    | Some rev ->
      run_capture_line repo [ "cat-file"; "-t"; rev ]
      >>| (function
      | "commit" -> Some { At_rev.remote; revision = Rev rev }
      | _ -> None)
  ;;
end

let remote_header =
  Re.(compile (seq [ bol; str "[remote \""; group (rep1 any); str "\"]"; eol ]))
;;

let remote_exists ~dir ~name =
  Path.relative dir "config"
  |> Io.lines_of_file
  |> List.find_opt ~f:(fun line ->
    match Re.exec_opt remote_header line with
    | Some groups ->
      let remote_name = Re.Group.get groups 1 in
      String.equal remote_name name
    | None -> false)
  |> Option.is_some
;;

let remote_add ~dir handle source =
  let git_config = Path.relative dir "config" in
  let existing = Io.read_file git_config in
  let stanza =
    sprintf
      {|%s

  [remote "%s"]
    url = %s
    fetch = +refs/heads/*:refs/remotes/%s/*
|}
      existing
      handle
      source
      handle
  in
  Io.write_file git_config stanza
;;

let add_repo ({ lock; dir } as t) ~allow_networking ~source =
  let handle = source |> Dune_digest.string |> Dune_digest.to_string in
  Fiber.Mutex.with_lock lock ~f:(fun () ->
    if not (remote_exists ~dir ~name:handle) then remote_add ~dir handle source;
    let remote : Remote.t = { repo = t; handle; default_branch = None } in
    let+ () = if allow_networking then Remote.update remote else Fiber.return () in
    remote)
;;
