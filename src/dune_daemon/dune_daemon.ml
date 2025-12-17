open Stdune
open Fiber.O
module Client = Dune_rpc_client.Client
module Where = Dune_rpc_client.Where

let ping () =
  let where = Where.default () in
  let* result =
    Fiber.map_reduce_errors
      (module Monoid.Unit)
      ~on_error:(fun _ -> Fiber.return ())
      (fun () ->
         let* conn = Client.Connection.connect where in
         match conn with
         | Error _ -> Fiber.return false
         | Ok conn ->
           let init =
             Dune_rpc_private.Initialize.Request.create
               ~id:(Dune_rpc_private.Id.make (Sexp.Atom "ping"))
           in
           Client.client ~private_menu:[] conn init ~f:(fun client ->
             let* decl =
               Client.Versioned.prepare_request
                 client
                 (Dune_rpc_private.Decl.Request.witness
                    Dune_rpc_private.Procedures.Public.ping)
             in
             match decl with
             | Error _ -> Fiber.return false
             | Ok decl ->
               let* response = Client.request client decl () in
               (match response with
                | Ok () -> Fiber.return true
                | Error _ -> Fiber.return false)))
  in
  match result with
  | Ok b -> Fiber.return b
  | Error () -> Fiber.return false
;;

let spawn_and_wait () =
  let dune_exe = Sys.executable_name in
  let args = [ dune_exe; "build"; "--passive-watch-mode" ] in
  let pid =
    let env = Env.to_unix Env.initial in
    Spawn.spawn
      ~prog:dune_exe
      ~argv:args
      ~env:(Spawn.Env.of_list env)
      ~stdin:(Lazy.force Dev_null.in_)
      ~stdout:(Lazy.force Dev_null.out)
      ~stderr:(Lazy.force Dev_null.out)
      ()
  in
  ignore (pid : int);
  (* Wait for daemon to be ready by pinging it *)
  let timeout_secs = 30.0 in
  let start = Time.now () in
  let rec wait_loop () =
    let* running = ping () in
    if running
    then Fiber.return ()
    else (
      let elapsed = Time.Span.to_secs (Time.diff (Time.now ()) start) in
      if elapsed > timeout_secs
      then User_error.raise [ Pp.text "Timed out waiting for daemon to start" ]
      else
        let* () = Fiber.return () in
        (* Small delay before retry *)
        Unix.sleepf 0.1;
        wait_loop ())
  in
  wait_loop ()
;;
