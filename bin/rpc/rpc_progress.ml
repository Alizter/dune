open Import
open Fiber.O
module Client = Dune_rpc_client.Client
module Version_error = Dune_rpc_private.Version_error

include struct
  open Dune_rpc
  module Diagnostic = Diagnostic
  module Progress = Progress
  module Job = Job
  module Sub = Sub
  module Conv = Conv
end

(** Utility module for generating [Map] modules for [Diagnostic]s and [Job]s which use
    their [Id] as keys. *)
module Id_map (Id : sig
    type t

    val compare : t -> t -> Ordering.t
    val sexp : (t, Conv.values) Conv.t
  end) =
struct
  include Map.Make (struct
      include Id

      let to_dyn t = Sexp.to_dyn (Conv.to_sexp Id.sexp t)
    end)
end

module Diagnostic_id_map = Id_map (Diagnostic.Id)
module Job_id_map = Id_map (Job.Id)

module Event = struct
  (** Events that the render loop will process. *)
  type t =
    | Diagnostics of Diagnostic.Event.t list
    | Jobs of Job.Event.t list
    | Progress of Progress.t
end

module State : sig
  (** Internal state of the render loop. *)
  type t

  (** Initial empty state. *)
  val init : unit -> t

  module Update : sig
    (** Incremental updates to the state. Computes increments of the state that
        will be used for efficient rendering. *)
    type t
  end

  val update : t -> Event.t -> Update.t

  (** Given a state update, render the update. *)
  val render : t -> Update.t -> unit
end = struct
  type t =
    { mutable diagnostics : Diagnostic.t Diagnostic_id_map.t
    ; mutable jobs : Job.t Job_id_map.t
    ; mutable progress : Progress.t
    }

  let init () =
    { diagnostics = Diagnostic_id_map.empty; jobs = Job_id_map.empty; progress = Waiting }
  ;;

  let done_status ~complete ~remaining ~failed state =
    Pp.textf
      "Done: %d%% (%d/%d, %d left%s) (jobs: %d)"
      (if complete + remaining = 0 then 0 else complete * 100 / (complete + remaining))
      complete
      (complete + remaining)
      remaining
      (match failed with
       | 0 -> ""
       | failed -> sprintf ", %d failed" failed)
      (Job_id_map.cardinal state.jobs)
  ;;

  let waiting_for_file_system_changes message =
    Pp.seq message (Pp.verbatim ", waiting for filesystem changes...")
  ;;

  let restarting_current_build message =
    Pp.seq message (Pp.verbatim ", restarting current build...")
  ;;

  let had_errors state =
    match Diagnostic_id_map.cardinal state.diagnostics with
    | 1 -> Pp.verbatim "Had 1 error"
    | n -> Pp.textf "Had %d errors" n
  ;;

  let status (state : t) =
    Console.Status_line.set
      (Live
         (fun () ->
           match (state.progress : Progress.t) with
           | Waiting -> Pp.verbatim "Initializing..."
           | In_progress { complete; remaining; failed } ->
             done_status ~complete ~remaining ~failed state
           | Interrupted ->
             Pp.tag User_message.Style.Error (Pp.verbatim "Source files changed")
             |> restarting_current_build
           | Success ->
             Pp.tag User_message.Style.Success (Pp.verbatim "Success")
             |> waiting_for_file_system_changes
           | Failed ->
             Pp.tag User_message.Style.Error (had_errors state)
             |> waiting_for_file_system_changes))
  ;;

  module Update = struct
    type t =
      | Update_status
      | Add_diagnostics of Diagnostic.t list
      | Refresh

    let jobs state jobs =
      let jobs =
        List.fold_left jobs ~init:state.jobs ~f:(fun acc job_event ->
          match (job_event : Job.Event.t) with
          | Start job -> Job_id_map.add_exn acc job.id job
          | Stop id -> Job_id_map.remove acc id)
      in
      state.jobs <- jobs;
      Update_status
    ;;

    let progress state progress =
      state.progress <- progress;
      Update_status
    ;;

    let diagnostics state diagnostics =
      let mode, diagnostics =
        List.fold_left
          diagnostics
          ~init:(`Add_only [], state.diagnostics)
          ~f:(fun (mode, acc) diag_event ->
            match (diag_event : Diagnostic.Event.t) with
            | Remove diag -> `Remove, Diagnostic_id_map.remove acc diag.id
            | Add diag ->
              ( (match mode with
                 | `Add_only diags -> `Add_only (diag :: diags)
                 | `Remove -> `Remove)
              , Diagnostic_id_map.add_exn acc diag.id diag ))
      in
      state.diagnostics <- diagnostics;
      match mode with
      | `Add_only update -> Add_diagnostics (List.rev update)
      | `Remove -> Refresh
    ;;
  end

  let update state (event : Event.t) =
    match event with
    | Jobs jobs -> Update.jobs state jobs
    | Progress progress -> Update.progress state progress
    | Diagnostics diagnostics -> Update.diagnostics state diagnostics
  ;;

  let render (state : t) (update : Update.t) =
    (* Don't print diagnostics during progress - they'll be shown at the end.
       Just update the status line. *)
    ignore update;
    status state
  ;;
end

(* Try to start a subscription, returning None if it fails. *)
let try_start_subscription ~client sub =
  Fiber.collect_errors (fun () -> Client.poll client sub)
  >>| function
  | Ok (Ok poller) -> Some poller
  | Ok (Error _version_error) -> None
  | Error _ -> None
;;

(* Loop that fetches events from a stream and pushes them to the event bus.
   Returns when the stream is cancelled or closed. Silently handles errors. *)
let fetch_loop ~(event : Event.t Fiber_event_bus.t) ~f poller =
  let rec loop () =
    Fiber.collect_errors (fun () -> Client.Stream.next poller)
    >>= (function
     | Ok (Some payload) -> Fiber_event_bus.push event (f payload)
     | Error _ | Ok None -> Fiber.return `Closed)
    >>= function
    | `Closed -> Fiber.return ()
    | `Ok -> loop ()
  in
  loop ()
;;

(* Render loop that processes events until build is done *)
let render_loop_until_done
      ~(event : Event.t Fiber_event_bus.t)
      ~(build_done : _ Fiber.Ivar.t)
  =
  let state = State.init () in
  let rec loop () =
    (* Check if build is done *)
    let* done_opt = Fiber.Ivar.peek build_done in
    match done_opt with
    | Some _ ->
      (* Build finished, stop rendering *)
      Console.Status_line.clear ();
      Fiber.return ()
    | None ->
      (* Check for events *)
      Fiber_event_bus.pop event
      >>= (function
       | `Closed ->
         Console.Status_line.clear ();
         Fiber.return ()
       | `Next ev ->
         let update = State.update state ev in
         State.render state update;
         loop ())
  in
  loop ()
;;

(* Helper to optionally run a fetch loop if stream is available *)
let maybe_fetch_loop ~event ~f = function
  | None -> Fiber.return ()
  | Some poller -> fetch_loop ~event ~f poller
;;

(* Helper to optionally cancel a stream *)
let maybe_cancel = function
  | None -> Fiber.return ()
  | Some stream -> Client.Stream.cancel stream
;;

(** Run an RPC request while displaying live progress.
    Subscribes to progress/diagnostics/jobs, executes the request,
    renders updates, returns when request completes.
    Gracefully handles subscription failures. *)
let run_with_progress ~(client : Client.t) ~(request : unit -> 'a Fiber.t) : 'a Fiber.t =
  let module Sub = Dune_rpc_private.Public.Sub in
  (* Try to start subscriptions - failures are non-fatal *)
  let* jobs_stream = try_start_subscription ~client Sub.running_jobs in
  let* progress_stream = try_start_subscription ~client Sub.progress in
  let* diagnostic_stream = try_start_subscription ~client Sub.diagnostic in
  (* If no subscriptions succeeded, just run the request without progress display *)
  let has_subscriptions =
    Option.is_some jobs_stream
    || Option.is_some progress_stream
    || Option.is_some diagnostic_stream
  in
  if not has_subscriptions
  then request ()
  else (
    let event_bus = Fiber_event_bus.create () in
    let build_done = Fiber.Ivar.create () in
    (* Cleanup function to cancel streams and close bus - called to unblock fibers *)
    let cleanup () =
      let* () = maybe_cancel jobs_stream in
      let* () = maybe_cancel progress_stream in
      let* () = maybe_cancel diagnostic_stream in
      let* () = Fiber_event_bus.close event_bus in
      Console.Status_line.clear ();
      Fiber.return ()
    in
    (* Run fetch loops, request, and render loop concurrently.
       When request finishes, cleanup to unblock other fibers. *)
    let+ (), result =
      Fiber.fork_and_join
        (fun () ->
           (* Subscription fibers - push events to bus, stop when streams are cancelled *)
           Fiber.all_concurrently_unit
             [ maybe_fetch_loop ~event:event_bus ~f:(fun x -> Event.Jobs x) jobs_stream
             ; maybe_fetch_loop
                 ~event:event_bus
                 ~f:(fun x -> Event.Progress x)
                 progress_stream
             ; maybe_fetch_loop
                 ~event:event_bus
                 ~f:(fun x -> Event.Diagnostics x)
                 diagnostic_stream
             ])
        (fun () ->
           Fiber.fork_and_join
             (fun () ->
                (* Send request, then cleanup to unblock other fibers *)
                Fiber.finalize
                  (fun () -> request ())
                  ~finally:(fun () ->
                    (* Always cleanup, even on exception/cancellation *)
                    cleanup ()))
             (fun () ->
                (* Render until build done or bus closed *)
                render_loop_until_done ~event:event_bus ~build_done))
    in
    fst result)
;;
