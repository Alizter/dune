open Import
open Types
open Exported_types

module Public = struct
  module Ping = struct
    let v1 = Decl.Request.make_current_gen ~req:Conv.unit ~resp:Conv.unit ~version:1
    let decl = Decl.Request.make ~method_:"ping" ~generations:[ v1 ]
  end

  module Diagnostics = struct
    module V1 = struct
      module Related = struct
        type t =
          { message : unit Pp.t
          ; loc : Loc.t
          }

        let sexp =
          let open Conv in
          let loc = field "loc" (required Loc.sexp) in
          let message = field "message" (required (sexp_pp unit)) in
          let to_ (loc, message) = { loc; message } in
          let from { loc; message } = loc, message in
          iso (record (both loc message)) to_ from
        ;;

        let to_diagnostic_related t : Diagnostic.Related.t =
          { message = t.message |> Pp.map_tags ~f:(fun _ -> User_message.Style.Details)
          ; loc = t.loc
          }
        ;;

        let of_diagnostic_related (t : Diagnostic.Related.t) =
          { message = t.message |> Pp.map_tags ~f:(fun _ -> ()); loc = t.loc }
        ;;
      end

      type t =
        { targets : Target.t list
        ; id : Diagnostic.Id.t
        ; message : unit Pp.t
        ; loc : Loc.t option
        ; severity : Diagnostic.severity option
        ; promotion : Diagnostic.Promotion.t list
        ; directory : string option
        ; related : Related.t list
        }

      let sexp_severity =
        let open Conv in
        enum [ "error", Diagnostic.Error; "warning", Warning ]
      ;;

      let sexp =
        let open Conv in
        let from { targets; message; loc; severity; promotion; directory; id; related } =
          targets, message, loc, severity, promotion, directory, id, related
        in
        let to_ (targets, message, loc, severity, promotion, directory, id, related) =
          { targets; message; loc; severity; promotion; directory; id; related }
        in
        let loc = field "loc" (optional Loc.sexp) in
        let message = field "message" (required (sexp_pp unit)) in
        let targets = field "targets" (required (list Target.sexp)) in
        let severity = field "severity" (optional sexp_severity) in
        let directory = field "directory" (optional string) in
        let promotion = field "promotion" (required (list Diagnostic.Promotion.sexp)) in
        let id = field "id" (required Diagnostic.Id.sexp) in
        let related = field "related" (required (list Related.sexp)) in
        iso
          (record (eight targets message loc severity promotion directory id related))
          to_
          from
      ;;

      let to_diagnostic t : Diagnostic.t =
        { targets = t.targets
        ; message = t.message |> Pp.map_tags ~f:(fun _ -> User_message.Style.Details)
        ; loc = t.loc
        ; severity = t.severity
        ; promotion = t.promotion
        ; directory = t.directory
        ; id = t.id
        ; related = t.related |> List.map ~f:Related.to_diagnostic_related
        }
      ;;

      let of_diagnostic (t : Diagnostic.t) =
        { targets = t.targets
        ; message = t.message |> Pp.map_tags ~f:(fun _ -> ())
        ; loc = t.loc
        ; severity = t.severity
        ; promotion = t.promotion
        ; directory = t.directory
        ; id = t.id
        ; related = t.related |> List.map ~f:Related.of_diagnostic_related
        }
      ;;
    end

    let v1 =
      Decl.Request.make_gen
        ~req:Conv.unit
        ~resp:(Conv.list V1.sexp)
        ~version:1
        ~upgrade_req:Fun.id
        ~downgrade_req:Fun.id
        ~upgrade_resp:(List.map ~f:V1.to_diagnostic)
        ~downgrade_resp:(List.map ~f:V1.of_diagnostic)
    ;;

    let v2 =
      Decl.Request.make_current_gen
        ~req:Conv.unit
        ~resp:(Conv.list Diagnostic.sexp)
        ~version:2
    ;;

    let decl = Decl.Request.make ~method_:"diagnostics" ~generations:[ v1; v2 ]
  end

  module Shutdown = struct
    let v1 = Decl.Notification.make_current_gen ~conv:Conv.unit ~version:1
    let decl = Decl.Notification.make ~method_:"shutdown" ~generations:[ v1 ]
  end

  module Format_dune_file = struct
    module V1 = struct
      let req =
        let open Conv in
        let path = field "path" (required string) in
        let contents = field "contents" (required string) in
        let to_ (path, contents) = path, `Contents contents in
        let from (path, `Contents contents) = path, contents in
        iso (record (both path contents)) to_ from
      ;;
    end

    let v1 = Decl.Request.make_current_gen ~req:V1.req ~resp:Conv.string ~version:1
    let decl = Decl.Request.make ~method_:"format-dune-file" ~generations:[ v1 ]
  end

  module Promote = struct
    let v1 = Decl.Request.make_current_gen ~req:Path.sexp ~resp:Conv.unit ~version:1
    let decl = Decl.Request.make ~method_:"promote" ~generations:[ v1 ]
  end

  module Build_dir = struct
    let v1 = Decl.Request.make_current_gen ~req:Conv.unit ~resp:Path.sexp ~version:1
    let decl = Decl.Request.make ~method_:"build_dir" ~generations:[ v1 ]
  end

  let ping = Ping.decl
  let diagnostics = Diagnostics.decl
  let shutdown = Shutdown.decl
  let format_dune_file = Format_dune_file.decl
  let promote = Promote.decl
  let build_dir = Build_dir.decl
end

module Server_side = struct
  module Abort = struct
    let v1 = Decl.Notification.make_current_gen ~conv:Message.sexp ~version:1
    let decl = Decl.Notification.make ~method_:"notify/abort" ~generations:[ v1 ]
  end

  module Log = struct
    let v1 = Decl.Notification.make_current_gen ~conv:Message.sexp ~version:1
    let decl = Decl.Notification.make ~method_:"notify/log" ~generations:[ v1 ]
  end

  let abort = Abort.decl
  let log = Log.decl
end

module Poll = struct
  let cancel_gen = Decl.Notification.make_current_gen ~conv:Id.sexp ~version:1

  module Name = struct
    include String

    let make s = s
  end

  type 'a t =
    { poll : (Id.t, 'a option) Decl.request
    ; cancel : Id.t Decl.notification
    ; name : Name.t
    }

  let make name generations =
    let poll = Decl.Request.make ~method_:("poll/" ^ name) ~generations in
    let cancel =
      Decl.Notification.make ~method_:("cancel-poll/" ^ name) ~generations:[ cancel_gen ]
    in
    { poll; cancel; name }
  ;;

  let poll t = t.poll
  let cancel t = t.cancel
  let name t = t.name

  module Progress = struct
    module V1 = struct
      type t =
        | Waiting
        | In_progress of
            { complete : int
            ; remaining : int
            }
        | Failed
        | Interrupted
        | Success

      let sexp =
        let open Conv in
        let waiting = constr "waiting" unit (fun () -> Waiting) in
        let failed = constr "failed" unit (fun () -> Failed) in
        let in_progress =
          let complete = field "complete" (required int) in
          let remaining = field "remaining" (required int) in
          constr
            "in_progress"
            (record (both complete remaining))
            (fun (complete, remaining) -> In_progress { complete; remaining })
        in
        let interrupted = constr "interrupted" unit (fun () -> Interrupted) in
        let success = constr "success" unit (fun () -> Success) in
        let constrs =
          List.map ~f:econstr [ waiting; failed; interrupted; success ]
          @ [ econstr in_progress ]
        in
        let serialize = function
          | Waiting -> case () waiting
          | In_progress { complete; remaining } -> case (complete, remaining) in_progress
          | Failed -> case () failed
          | Interrupted -> case () interrupted
          | Success -> case () success
        in
        sum constrs serialize
      ;;

      let to_progress : t -> Progress.t = function
        | Waiting -> Waiting
        | In_progress { complete; remaining } ->
          In_progress { complete; remaining; failed = 0 }
        | Failed -> Failed
        | Interrupted -> Interrupted
        | Success -> Success
      ;;

      let of_progress : Progress.t -> t = function
        | Waiting -> Waiting
        | In_progress { complete; remaining; failed = _ } ->
          In_progress { complete; remaining }
        | Failed -> Failed
        | Interrupted -> Interrupted
        | Success -> Success
      ;;
    end

    let name = "progress"

    let v1 =
      Decl.Request.make_gen
        ~version:1
        ~req:Id.sexp
        ~resp:(Conv.option V1.sexp)
        ~upgrade_req:Fun.id
        ~downgrade_req:Fun.id
        ~upgrade_resp:(Option.map ~f:V1.to_progress)
        ~downgrade_resp:(Option.map ~f:V1.of_progress)
    ;;

    let v2 =
      Decl.Request.make_current_gen
        ~version:2
        ~req:Id.sexp
        ~resp:(Conv.option Progress.sexp)
    ;;
  end

  module Diagnostic = struct
    let name = "diagnostic"

    let v1 =
      Decl.Request.make_current_gen
        ~req:Id.sexp
        ~resp:(Conv.option (Conv.list Diagnostic.Event.sexp))
        ~version:1
    ;;
  end

  module Job = struct
    let name = "running-jobs"

    let v1 =
      Decl.Request.make_current_gen
        ~req:Id.sexp
        ~resp:(Conv.option (Conv.list Job.Event.sexp))
        ~version:1
    ;;
  end

  let progress =
    let open Progress in
    make name [ v1; v2 ]
  ;;

  let diagnostic =
    let open Diagnostic in
    make name [ v1 ]
  ;;

  let running_jobs =
    let open Job in
    make name [ v1 ]
  ;;
end
