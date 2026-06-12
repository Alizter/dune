open Import

(* Unique tags per resolver, so callers can compare resolvers reliably
   (e.g. to gate workspace-only behaviour) without depending on physical
   equality of closures. *)
module Id = Id.Make ()

type t =
  { id : Id.t
  ; resolve : Path.Source.t -> Path.Outside_build_dir.t
  }

let workspace =
  { id = Id.gen (); resolve = (fun p -> Path.Outside_build_dir.In_source_dir p) }
;;

let create resolve = { id = Id.gen (); resolve }
let resolve t = t.resolve
let equal a b = Id.equal a.id b.id
let is_workspace t = equal t workspace
