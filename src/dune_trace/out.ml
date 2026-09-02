open Stdune

type runtime_clock =
  { dune : Time.t
  ; runtime : int64
  }

type runtime =
  { callbacks : Runtime.Callbacks.t
  ; cursor : Runtime.cursor
  ; cleanup_dir : string option
  }

type t =
  { fd : Fd.t
  ; buf : Buffer.t
  ; cats : Category.Set.t
  ; mutex : Mutex.t
  ; alloc : Alloc.t option
  ; runtime : runtime option
  }

let fd t = t.fd
let cats t = t.cats
let alloc t = t.alloc

(* CR-someday rgrinberg: remove this once we drop support for < 5.2 *)
external write_bigstring
  :  Unix.file_descr
  -> Bigstringaf.t
  -> int
  -> int
  -> int
  = "dune_trace_write"

let flush_unlocked =
  (* This loop will almost always result in a single write, but we make sure to
     write everything (albeit inefficiently) if the user is running out of disk
     space, is on NFS, or some exotic operation system that doesn't give us
     atomic writes with [O_APPEND] *)
  let rec loop t pos len =
    if len = 0
    then Buffer.clear t.buf
    else (
      match
        write_bigstring
          (Fd.unsafe_to_unix_file_descr t.fd)
          (Buffer.buf t.buf)
          pos
          (Buffer.pos t.buf - pos)
      with
      | n -> loop t (pos + n) (len - n)
      | exception e ->
        let () =
          (* inefficient, but we just want to make sure we're preserving the
             invariants of [t] even if we fail for some odd reason. *)
          Buffer.drop t.buf pos
        in
        raise e)
  in
  fun t -> loop t 0 (Buffer.pos t.buf)
;;

let close t =
  Mutex.protect t.mutex (fun () ->
    if not (Fd.is_closed t.fd)
    then (
      flush_unlocked t;
      Fd.close t.fd))
;;

let prepare_runtime_shutdown t =
  Option.iter t.runtime ~f:(fun { cleanup_dir; _ } ->
    Runtime.pause ();
    (* The runtime keeps a relative path to the ring buffer and removes it after
       OCaml exit handlers finish. Leave the process in that directory now that
       Dune's trace-dependent exit handlers have run. *)
    Option.iter cleanup_dir ~f:Unix.chdir)
;;

let to_buffer t sexp =
  let rec loop = function
    | Csexp.Atom str ->
      Buffer.add_string t.buf (string_of_int (String.length str));
      Buffer.add_char t.buf ':';
      Buffer.add_string t.buf str
    | List e ->
      Buffer.add_char t.buf '(';
      List.iter ~f:loop e;
      Buffer.add_char t.buf ')'
  in
  loop sexp
;;

let emit_buffered t event =
  let needed = Csexp.serialised_length event in
  if Buffer.available t.buf < needed
  then (
    let new_size = max (Buffer.pos t.buf + needed) (2 * Buffer.max_size t.buf) in
    Buffer.resize t.buf new_size);
  to_buffer t event
;;

let emit ?(buffered = false) t event =
  Mutex.protect t.mutex (fun () ->
    if not (Fd.is_closed t.fd)
    then (
      emit_buffered t event;
      if not buffered then flush_unlocked t))
;;

let flush t =
  Mutex.protect t.mutex (fun () -> if not (Fd.is_closed t.fd) then flush_unlocked t)
;;

let emit_runtime t =
  Option.iter t.runtime ~f:(fun { callbacks; cursor; _ } ->
    (* Avoid recording allocations done while consuming runtime events. *)
    Runtime.pause ();
    Exn.protect ~finally:Runtime.resume ~f:(fun () ->
      ignore (Runtime.read_poll cursor callbacks None);
      flush t))
;;

let start t k : Event.Async.t option =
  match t with
  | None -> None
  | Some _ ->
    let event_data = k () in
    let start = Time.now () in
    Some (Event.Async.create ~event_data ~start)
;;

let finish t event =
  match event with
  | None -> ()
  | Some { Event.Async.start; event_data = { args; cat; name } } ->
    let dur =
      let stop = Time.now () in
      Time.diff stop start
    in
    let event = Event.Event.complete ?args ~start ~dur cat ~name in
    emit t event
;;

let setup_runtime ~events_dir =
  let start () =
    Runtime.start ();
    Runtime.pause ();
    let cursor = Runtime.create_cursor None in
    let cleanup_dir =
      match Runtime.path () with
      | Some path when Filename.is_relative path -> Some (Unix.getcwd ())
      | None | Some _ -> None
    in
    cursor, cleanup_dir
  in
  match Runtime.path (), events_dir with
  | Some _, _ | None, None -> start ()
  | None, Some path ->
    (* [OCAML_RUNTIME_EVENTS_DIR] is cached before OCaml code starts. Starting
       runtime events from this directory is therefore necessary when tracing
       enables them later. The cursor must be opened before restoring [cwd]. *)
    let dir = Path.relative (Path.parent_exn path) ".runtime-events" in
    Path.mkdir_p dir;
    let dir = Path.to_absolute_filename dir in
    Unix.putenv "OCAML_RUNTIME_EVENTS_DIR" dir;
    let cwd = Unix.getcwd () in
    Unix.chdir dir;
    Exn.protect ~f:start ~finally:(fun () -> Unix.chdir cwd)
;;

let runtime_callbacks =
  (* Runtime event timestamps use the runtime's clock rather than the wall-clock
    timestamps used by dune trace. Keep one sample from both clocks to translate
    runtime timestamps into the trace clock. *)
  let runtime_clock_base clock timestamp =
    match !clock with
    | Some base -> base
    | None ->
      let runtime =
        match Runtime.current_timestamp () with
        | None -> timestamp
        | Some now -> Runtime.Timestamp.to_int64 now
      in
      let base = { dune = Time.now (); runtime } in
      clock := Some base;
      base
  in
  let time_of_runtime_timestamp clock timestamp =
    let timestamp = Runtime.Timestamp.to_int64 timestamp in
    let { dune; runtime } = runtime_clock_base clock timestamp in
    let delta = Int64.sub timestamp runtime |> Int64.to_int |> Time.Span.of_ns in
    Time.add dune delta
  in
  fun t ->
    let clock = ref None in
    let emit event = emit (Lazy.force t) ~buffered:true event in
    let time timestamp = time_of_runtime_timestamp clock timestamp in
    Runtime.Callbacks.create
      ~runtime_begin:(fun ring_id timestamp phase ->
        emit (Event.runtime ring_id (time timestamp) `Begin phase))
      ~runtime_end:(fun ring_id timestamp phase ->
        emit (Event.runtime ring_id (time timestamp) `End phase))
      ~runtime_counter:(fun ring_id timestamp name value ->
        emit (Event.runtime_counter ring_id (time timestamp) name value))
      ()
;;

let create how =
  let cats = Category.enabled () in
  let runtime_enabled = Category.Set.mem cats Runtime in
  let runtime_cursor =
    if runtime_enabled
    then
      Some
        (setup_runtime
           ~events_dir:
             (match how with
              | `Fd _ -> None
              | `Path path -> Some path))
    else None
  in
  let fd =
    match how with
    | `Fd fd -> fd
    | `Path path ->
      Unix.openfile
        (Path.to_string path)
        [ O_TRUNC; O_APPEND; O_CLOEXEC; O_WRONLY; O_CREAT ]
        0o644
      |> Fd.unsafe_of_unix_file_descr
  in
  let buf = Buffer.create (1 lsl 16) in
  let alloc = if Category.Set.mem cats Alloc then Some (Alloc.start ()) else None in
  let rec t =
    lazy { fd; cats; buf; mutex = Mutex.create (); alloc; runtime = Lazy.force runtime }
  and runtime =
    lazy
      (match runtime_cursor with
       | None -> None
       | Some (cursor, cleanup_dir) ->
         let callbacks = runtime_callbacks t in
         Some { callbacks; cursor; cleanup_dir })
  in
  let t = Lazy.force t in
  if runtime_enabled then Runtime.resume ();
  t
;;
