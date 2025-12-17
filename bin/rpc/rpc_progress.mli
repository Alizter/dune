(** Progress display for RPC-forwarded builds.

    This module provides infrastructure for displaying live progress, diagnostics,
    and job information when builds are executed via RPC (daemon mode, lock
    contention, etc.) rather than locally. *)

module Client := Dune_rpc_client.Client

(** Run an RPC request while displaying live progress.

    Subscribes to progress, diagnostics, and job events from the RPC server,
    renders them to the console, and returns when the request completes.

    This provides the same user experience as local builds - showing progress
    percentage, running jobs, and live diagnostics - even when the build is
    happening in another dune process. *)
val run_with_progress : client:Client.t -> request:(unit -> 'a Fiber.t) -> 'a Fiber.t
