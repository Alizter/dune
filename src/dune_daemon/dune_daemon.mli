(** Build daemon management for Dune.

    This module provides functionality to detect and spawn a build daemon
    process. The daemon is a dune process running in passive watch mode
    that serves build requests via RPC. *)

(** Send an RPC ping to verify the daemon is running and responsive.
    Returns [true] if the daemon responds, [false] otherwise. *)
val ping : unit -> bool Fiber.t

(** Spawn a daemon process and wait for it to be ready to accept connections.
    The daemon runs [dune build --passive-watch] in the background. *)
val spawn_and_wait : unit -> unit Fiber.t
