open Import
open Fiber.O

let action_trace_root =
  lazy
    (let root = Path.Build.(relative root ".action-trace") in
     Path.mkdir_p (Path.build root);
     root)
;;

let root () = Path.build (Lazy.force action_trace_root)

type t =
  { dir : Path.Build.t
  ; digest : string
  }

let add_to_env t env =
  Env.add
    env
    ~var:Env.Var._DUNE_ACTION_TRACE_DIR
    ~value:(Path.to_absolute_filename (Path.build t.dir))
;;

let create digest =
  let root = Lazy.force action_trace_root in
  let digest = Dune_digest.to_string digest in
  { dir = Path.Build.relative root digest; digest }
;;

let collect_file file ~digest =
  let file = Path.build file in
  match
    Filename.Extension.Or_empty.check (Path.extension file) Filename.Extension.json
  with
  | true -> () (* CR-soon rgrinberg: handle json payloads as well *)
  | false ->
    Io.with_file_in ~binary:true file ~f:(fun chan ->
      let rec loop () =
        match Csexp.input_opt chan with
        | Ok None -> ()
        | Error _ ->
          User_error.raise
            [ Pp.textf "invalid action trace in %s" (Path.to_string_maybe_quoted file) ]
        | Ok (Some s) ->
          Dune_trace.emit ~buffered:true Action (fun () ->
            Dune_trace.Event.Action.trace ~digest s);
          loop ()
      in
      loop ())
;;

let destroy { dir; _ } = Path.rm_rf (Path.build dir)

let collect { dir; digest } =
  let* () = Fiber.return () in
  let unrecognized = Queue.create () in
  let errors = Queue.create () in
  let root = dir in
  let root_path = Path.build root in
  let build_dir_of dir =
    if String.equal dir "" then root else Path.Build.relative root dir
  in
  let build_path_of ~dir fname = Path.Build.relative_fname (build_dir_of dir) fname in
  let push_broken_symlink ~dir fname error =
    let path = build_path_of ~dir fname in
    let error =
      User_message.make
        [ Pp.textf "broken symlink %s" (Path.Build.to_string_maybe_quoted path)
        ; Unix_error.Detailed.pp error
        ]
    in
    Queue.push errors (User_error.E error)
  in
  let on_file ~dir fname () =
    let file = build_path_of ~dir fname in
    try collect_file file ~digest with
    | exn -> Queue.push errors exn
  in
  let on_other ~dir fname _kind () = Queue.push unrecognized (build_path_of ~dir fname) in
  let on_symlink ~dir fname () =
    let path = Path.build (build_path_of ~dir fname) in
    match Path.Untracked.stat path with
    | Ok { Unix.st_kind = kind; _ } -> (), Some kind
    | Error error ->
      push_broken_symlink ~dir fname error;
      (), None
  in
  Fpath.traverse
    ~dir:(Path.to_string root_path)
    ~init:()
    ~on_file
    ~on_other:(`Call on_other)
    ~on_symlink:(`Call on_symlink)
    ~on_error:
      (`Call
          (fun ~dir error () ->
            match error with
            | Unix.ENOENT, _, _ -> ()
            | _ ->
              let dir = build_dir_of dir in
              let error =
                User_error.make
                  [ Pp.textf "unreadable dir %s" (Path.Build.to_string_maybe_quoted dir)
                  ; Unix_error.Detailed.pp error
                  ]
              in
              Queue.push errors (User_error.E error)))
    ();
  Dune_trace.flush ();
  (match Queue.to_list unrecognized with
   | [] -> ()
   | unrecognized ->
     let error =
       User_message.make
         [ Pp.text "unrecognized files"
         ; Pp.enumerate unrecognized ~f:(fun f ->
             Pp.verbatim (Path.Build.to_string_maybe_quoted f))
         ]
     in
     Queue.push errors (User_error.E error));
  match Queue.to_list errors with
  | [] -> Fiber.return ()
  | errors ->
    let errors =
      (* A bit of a useless callstack, but good enough for our purposes here. *)
      let backtrace = Printexc.get_callstack 10 in
      List.map errors ~f:(fun exn -> { Exn_with_backtrace.exn; backtrace })
    in
    Fiber.reraise_all errors
;;
