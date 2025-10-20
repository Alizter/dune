open! Import
open Pkg_common
module Package_universe = Dune_pkg.Package_universe
module Opam_repo = Dune_pkg.Opam_repo
module Package_version = Dune_pkg.Package_version
module Opam_solver = Dune_pkg.Opam_solver

let info =
  let doc = "Validate that a lockdir contains a solution for local packages" in
  let man = [ `S "DESCRIPTION"; `P doc ] in
  Cmd.info "validate-lockdir" ~doc ~man
;;

(* CR-someday alizter: The logic here is a little more complicated than it needs
   to be and can be simplified. *)

let enumerate_lock_dirs_by_path ~lock_dirs () =
  let open Memo.O in
  let* per_contexts =
    Workspace.workspace () >>| Pkg_common.Lock_dirs_arg.lock_dirs_of_workspace lock_dirs
  in
  per_contexts
  |> Memo.List.filter_map ~f:(fun lock_dir_path ->
    let path = Path.source lock_dir_path in
    if not (Path.exists path)
    then Memo.return None
    else
      let+ result = Pkg_common.load_lock_dir lock_dir_path in
      Some
        (match result with
         | Ok lock_dir -> Ok (lock_dir_path, lock_dir)
         | Error user_message -> Error (lock_dir_path, `Parse_error user_message)))
;;

let validate_lock_dirs ~lock_dirs () =
  let open Fiber.O in
  let* lock_dirs_by_path, local_packages =
    Memo.both (enumerate_lock_dirs_by_path ~lock_dirs ()) Pkg_common.find_local_packages
    |> Memo.run
  in
  if List.is_empty lock_dirs_by_path
  then
    let+ () = Fiber.return () in
    Console.print [ Pp.text "No lockdirs to validate." ]
  else
    let+ universes =
      Fiber.parallel_map lock_dirs_by_path ~f:(function
        | Error (p, e) -> Fiber.return (Some (Path.source p, e))
        | Ok (lock_dir_path, lock_dir) ->
          let lock_dir_path = Path.source lock_dir_path in
          let+ platform = solver_env_from_system_and_context ~lock_dir_path in
          (match Package_universe.create ~platform local_packages lock_dir with
           | Ok _ -> None
           | Error e -> Some (lock_dir_path, `Lock_dir_out_of_sync e)))
      >>| List.filter_opt
    in
    match universes with
    | [] -> ()
    | errors_by_path ->
      List.iter errors_by_path ~f:(fun (path, error) ->
        match error with
        | `Parse_error error ->
          User_message.prerr
            (User_message.make
               [ Pp.textf "Failed to parse lockdir %s:" (Path.to_string_maybe_quoted path)
               ; User_message.pp error
               ])
        | `Lock_dir_out_of_sync error ->
          User_message.prerr
            (User_message.make
               [ Pp.textf
                   "Lockdir %s does not contain a solution for local packages:"
                   (Path.to_string path)
               ]);
          User_message.prerr error);
      User_error.raise
        [ Pp.text "Some lockdirs do not contain solutions for local packages:"
        ; Pp.enumerate errors_by_path ~f:(fun (path, _) -> Pp.text (Path.to_string path))
        ]
;;

let term =
  let+ builder = Common.Builder.term
  and+ lock_dirs = Pkg_common.Lock_dirs_arg.term in
  let common, config = Common.init builder in
  let once () =
    let request (setup : Import.Main.build_system) =
      let dir = Path.(relative root) (Common.prefix_target common ".") in
      let open Action_builder.O in
      (* CR-someday Alizter: We shouldn't be building anything here ideally,
         only validating the source lock directory, but we need to rethink how
         we might encounter those. *)
      let* () =
        Alias.in_dir
          ~name:Dune_rules.Alias.pkg_lock
          ~recursive:true
          ~contexts:setup.contexts
          dir
        |> Alias.request
      in
      Action_builder.of_memo
        (Memo.of_thunk (fun () ->
           Memo.of_reproducible_fiber
           @@
           let open Fiber.O in
           Pkg_common.check_pkg_management_enabled () >>> validate_lock_dirs ~lock_dirs ()))
    in
    let open Fiber.O in
    Build.run_build_system ~common ~request
    >>| function
    | Ok () -> ()
    | Error `Already_reported -> raise Dune_util.Report_error.Already_reported
  in
  Scheduler.go_with_rpc_server ~common ~config once
;;

let command = Cmd.v info term
