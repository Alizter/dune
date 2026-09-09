(** Automatic startup and discovery of workspace build servers. *)

open Import

type t

(** Take the build lock for a local build, or select a server to connect to.
    Only non-watch commands may automatically start a daemon. *)
val prepare : common:Common.t -> config:Dune_config.t -> [ `Local | `Rpc of t ]

(** Start the selected daemon if needed and connect to it. Must run inside a
    scheduler without its own RPC server. *)
val connect : t -> (Root.Rpc.Client.Connection.t * Global_lock.Lock_held_by.t) Fiber.t

(** Internal entry point for the server process. *)
val command : unit Cmd.t
