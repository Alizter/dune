open Import
module Pkg_dev_tool = Dune_rules.Pkg_dev_tool
module Tool_build = Dune_rules.Tool_build
module Tool_stanza = Source.Tool_stanza

let dev_tool_bin_dirs =
  List.map Pkg_dev_tool.all ~f:(fun tool ->
    Pkg_dev_tool.exe_path tool |> Path.Build.parent_exn |> Path.build)
;;


let add_dev_tools_to_path env =
  List.fold_left dev_tool_bin_dirs ~init:env ~f:(fun acc dir -> Env_path.cons acc ~dir)
;;

let dev_tool_exe_path dev_tool = Path.build @@ Pkg_dev_tool.exe_path dev_tool

let dev_tool_build_target dev_tool =
  Dune_lang.Dep_conf.File
    (Dune_lang.String_with_vars.make_text
       Loc.none
       (Path.to_string (dev_tool_exe_path dev_tool)))
;;

let build_dev_tool_directly common dev_tool =
  let open Fiber.O in
  let+ result =
    Build.run_build_system ~common ~request:(fun _build_system ->
      let open Action_builder.O in
      let* () = dev_tool |> Lock_dev_tool.lock_dev_tool |> Action_builder.of_memo in
      (* Make sure the tool's lockdir is generated before building the tool. *)
      Action_builder.path (dev_tool_exe_path dev_tool))
  in
  match result with
  | Error `Already_reported -> raise Dune_util.Report_error.Already_reported
  | Ok () -> ()
;;

let build_dev_tool_via_rpc builder lock_held_by dev_tool =
  let target = dev_tool_build_target dev_tool in
  let targets = Rpc.Rpc_common.prepare_targets [ target ] in
  let open Fiber.O in
  Rpc.Rpc_common.fire_request
    ~name:"build"
    ~wait:true
    ~lock_held_by
    builder
    Dune_rpc_impl.Decl.build
    targets
  >>| Rpc.Rpc_common.wrap_build_outcome_exn ~print_on_success:false
;;

let lock_and_build_dev_tool ~common ~config builder dev_tool =
  let open Fiber.O in
  match Dune_util.Global_lock.lock ~timeout:None with
  | Error lock_held_by ->
    Scheduler_setup.no_build_no_rpc ~config (fun () ->
      let* () = Lock_dev_tool.lock_dev_tool dev_tool |> Memo.run in
      build_dev_tool_via_rpc builder lock_held_by dev_tool)
  | Ok () ->
    Scheduler_setup.go_with_rpc_server ~common ~config (fun () ->
      build_dev_tool_directly common dev_tool)
;;

let run_dev_tool workspace_root dev_tool ~args =
  let exe_name = Pkg_dev_tool.exe_name dev_tool in
  let exe_path_string = Path.to_string (dev_tool_exe_path dev_tool) in
  Console.print_user_message
    (Dune_rules.Pkg_build_progress.format_user_message
       ~verb:"Running"
       ~object_:(User_message.command (String.concat ~sep:" " (exe_name :: args))));
  Console.finish ();
  let env = add_dev_tools_to_path Env.initial in
  restore_cwd_and_execve workspace_root exe_path_string args env
;;

let lock_build_and_run_dev_tool ~common ~config builder dev_tool ~args =
  lock_and_build_dev_tool ~common ~config builder dev_tool;
  run_dev_tool (Common.root common) dev_tool ~args
;;

let which_command dev_tool =
  let exe_path = dev_tool_exe_path dev_tool in
  let exe_name = Pkg_dev_tool.exe_name dev_tool in
  let term =
    let+ builder = Common.Builder.term
    and+ allow_not_installed =
      Arg.(
        value
        & flag
        & info
            [ "allow-not-installed" ]
            ~doc:
              (Some
                 (sprintf
                    "If %s is not installed as a dev tool, still print where it would be \
                     installed."
                    exe_name)))
    in
    let _ : Common.t * Dune_config_file.Dune_config.t = Common.init builder in
    if allow_not_installed || Path.exists exe_path
    then print_endline (Path.to_string exe_path)
    else User_error.raise [ Pp.textf "%s is not installed as a dev tool" exe_name ]
  in
  let info =
    let doc =
      sprintf
        "Prints the path to the %s dev tool executable if it exists, errors out \
         otherwise."
        exe_name
    in
    Cmd.info exe_name ~doc
  in
  Cmd.v info term
;;

let install_command dev_tool =
  let exe_name = Pkg_dev_tool.exe_name dev_tool in
  let term =
    let+ builder = Common.Builder.term in
    let common, config = Common.init builder in
    lock_and_build_dev_tool ~common ~config builder dev_tool
  in
  let info =
    let doc = sprintf "Install %s as a dev tool" exe_name in
    Cmd.info exe_name ~doc
  in
  Cmd.v info term
;;

let exec_command dev_tool =
  let exe_name = Pkg_dev_tool.exe_name dev_tool in
  let term =
    let+ builder = Common.Builder.term
    (* CR-someday Alizter: document this option *)
    and+ args = Arg.(value & pos_all string [] (info [] ~docv:"ARGS" ~doc:None)) in
    let common, config = Common.init builder in
    lock_build_and_run_dev_tool ~common ~config builder dev_tool ~args
  in
  let info =
    let doc =
      sprintf
        {|Wrapper for running %s intended to be run automatically
          by a text editor. All positional arguments will be passed to the
          %s executable (pass flags to %s after the '--'
          argument, such as 'dune tools exec %s -- --help').|}
        exe_name
        exe_name
        exe_name
        exe_name
    in
    Cmd.info exe_name ~doc
  in
  Cmd.v info term
;;

let env_command =
  let term =
    let+ builder = Common.Builder.term
    and+ fish =
      Arg.(
        value
        & flag
        & info
            [ "fish" ]
            ~doc:(Some "Print command for the fish shell rather than POSIX shells"))
    in
    let _ : Common.t * Dune_config.t = Common.init builder in
    if fish
    then (
      let space_separated_dev_tool_paths =
        List.map dev_tool_bin_dirs ~f:Path.to_string_maybe_quoted
        |> String.concat ~sep:" "
      in
      print_endline (sprintf "fish_add_path --prepend %s" space_separated_dev_tool_paths))
    else (
      let initial_path = Env.get Env.initial Env_path.var in
      let new_path =
        List.fold_left dev_tool_bin_dirs ~init:initial_path ~f:(fun acc bin_dir ->
          Some (Bin.cons_path bin_dir ~_PATH:acc))
      in
      match new_path with
      | None -> ()
      | Some new_path -> print_endline (sprintf "export %s=%s" Env_path.var new_path))
  in
  let info =
    let doc =
      "Print a command which can be eval'd to enter an environment where all dev tools \
       are runnable as commands."
    in
    Cmd.info "env" ~doc
  in
  Cmd.v info term
;;

(* ========== Generic Tool Support ========== *)

(** Get the exe path for a generic tool package *)
let generic_tool_exe_path package_name =
  let executable = Package_name.to_string package_name in
  Path.build @@ Tool_build.exe_path ~package_name ~executable
;;

(** Build target for a generic tool *)
let generic_tool_build_target package_name =
  Dune_lang.Dep_conf.File
    (Dune_lang.String_with_vars.make_text
       Loc.none
       (Path.to_string (generic_tool_exe_path package_name)))
;;

let build_generic_tool_directly common package_name =
  let open Fiber.O in
  let+ result =
    Build.run_build_system ~common ~request:(fun _build_system ->
      let open Action_builder.O in
      (* Only lock if lock dir doesn't exist - don't re-lock on every run *)
      let* () = package_name |> Lock_tool.lock_tool_if_needed |> Action_builder.of_memo in
      Action_builder.path (generic_tool_exe_path package_name))
  in
  match result with
  | Error `Already_reported -> raise Dune_util.Report_error.Already_reported
  | Ok () -> ()
;;

let build_generic_tool_via_rpc builder lock_held_by package_name =
  let target = generic_tool_build_target package_name in
  let targets = Rpc.Rpc_common.prepare_targets [ target ] in
  let open Fiber.O in
  Rpc.Rpc_common.fire_request
    ~name:"build"
    ~wait:true
    ~lock_held_by
    builder
    Dune_rpc_impl.Decl.build
    targets
  >>| Rpc.Rpc_common.wrap_build_outcome_exn ~print_on_success:false
;;

let lock_and_build_generic_tool ~common ~config builder package_name =
  let open Fiber.O in
  match Dune_util.Global_lock.lock ~timeout:None with
  | Error lock_held_by ->
    Scheduler_setup.no_build_no_rpc ~config (fun () ->
      let* () = Lock_tool.lock_tool package_name |> Memo.run in
      build_generic_tool_via_rpc builder lock_held_by package_name)
  | Ok () ->
    Scheduler_setup.go_with_rpc_server ~common ~config (fun () ->
      build_generic_tool_directly common package_name)
;;

let run_generic_tool workspace_root package_name ~args =
  let exe_name = Package_name.to_string package_name in
  let exe_path_string = Path.to_string (generic_tool_exe_path package_name) in
  Console.print_user_message
    (Dune_rules.Pkg_build_progress.format_user_message
       ~verb:"Running"
       ~object_:(User_message.command (String.concat ~sep:" " (exe_name :: args))));
  Console.finish ();
  let env = add_dev_tools_to_path Env.initial in
  restore_cwd_and_execve workspace_root exe_path_string args env
;;

let lock_build_and_run_generic_tool ~common ~config builder package_name ~args =
  lock_and_build_generic_tool ~common ~config builder package_name;
  run_generic_tool (Common.root common) package_name ~args
;;

(** Generic exec term for any package (used as default in group) *)
let generic_exec_term =
  let+ builder = Common.Builder.term
  and+ package =
    Arg.(required & pos 0 (some string) None (info [] ~docv:"PACKAGE" ~doc:(Some "The opam package name to execute")))
  and+ args = Arg.(value & pos_right 0 string [] (info [] ~docv:"ARGS" ~doc:None)) in
  let common, config = Common.init builder in
  let package_name = Package_name.of_string package in
  lock_build_and_run_generic_tool ~common ~config builder package_name ~args
;;

(** Generic exec command for any package *)
let generic_exec_command =
  let info =
    let doc =
      "Execute any opam package as a tool. The package will be locked and built if \
       necessary. Pass arguments to the tool after '--'."
    in
    Cmd.info "exec" ~doc
  in
  Cmd.v info generic_exec_term
;;

(** Lock a generic tool (no build) *)
let lock_generic_tool ~common ~config package_name =
  let open Fiber.O in
  Scheduler_setup.go_with_rpc_server ~common ~config (fun () ->
    let+ () = Lock_tool.lock_tool package_name |> Memo.run in
    Console.print_user_message
      (User_message.make
         [ Pp.textf "Locked %s. Run 'dune tools run %s' to build and execute."
             (Package_name.to_string package_name)
             (Package_name.to_string package_name)
         ]))
;;

(** Lock a generic tool at a specific version (no build) *)
let lock_generic_tool_at_version ~common ~config package_name ~version =
  let open Fiber.O in
  Scheduler_setup.go_with_rpc_server ~common ~config (fun () ->
    let+ () =
      Lock_tool.lock_tool_at_version ~package_name ~version ~compiler_compatible:false
      |> Memo.run
    in
    let version_str =
      match version with
      | Some v -> Printf.sprintf " (%s)" (Package_version.to_string v)
      | None -> ""
    in
    Console.print_user_message
      (User_message.make
         [ Pp.textf "Locked %s%s. Run 'dune tools run %s' to build and execute."
             (Package_name.to_string package_name)
             version_str
             (Package_name.to_string package_name)
         ]))
;;

(** Generic lock term for any package *)
let generic_lock_term =
  let+ builder = Common.Builder.term
  and+ package =
    Arg.(required & pos 0 (some string) None (info [] ~docv:"PACKAGE" ~doc:(Some "The opam package name to lock")))
  and+ version =
    Arg.(value & opt (some string) None (info [ "version" ] ~docv:"VERSION" ~doc:"Version constraint (e.g., 0.26.2)"))
  in
  let common, config = Common.init builder in
  let package_name = Package_name.of_string package in
  let version = Option.map version ~f:Package_version.of_string in
  lock_generic_tool_at_version ~common ~config package_name ~version
;;

(** Generic lock command for any package *)
let generic_lock_command =
  let info =
    let doc = "Lock any opam package as a tool. Creates a lock directory without building." in
    Cmd.info "lock" ~doc
  in
  Cmd.v info generic_lock_term
;;

(** Generic which term for any package (used as default in group) *)
let generic_which_term =
  let+ builder = Common.Builder.term
  and+ package =
    Arg.(required & pos 0 (some string) None (info [] ~docv:"PACKAGE" ~doc:(Some "The opam package name")))
  and+ allow_not_installed =
    Arg.(
      value
      & flag
      & info
          [ "allow-not-installed" ]
          ~doc:(Some "Print where the tool would be installed even if not installed yet."))
  in
  let _ : Common.t * Dune_config_file.Dune_config.t = Common.init builder in
  let package_name = Package_name.of_string package in
  let exe_path = generic_tool_exe_path package_name in
  if allow_not_installed || Path.exists exe_path
  then print_endline (Path.to_string exe_path)
  else User_error.raise [ Pp.textf "%s is not installed as a tool" package ]
;;

(** Generic which command for any package *)
let generic_which_command =
  let info =
    let doc = "Print the path to a tool's executable. Errors if the tool is not installed." in
    Cmd.info "which" ~doc
  in
  Cmd.v info generic_which_term
;;
