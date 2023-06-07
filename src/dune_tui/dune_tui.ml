open Stdune

module Tui () = struct
  module Term = Notty_unix.Term
  module A = Notty.A
  module I = Notty.I

  let term = Term.create ~nosig:false ()

  
  let term_input_fds, _ = Term.fds term
  let start () = Unix.set_nonblock term_input_fds

  type ui_attrs =
    { divider_attr : A.t
          (** style for diving visual elements like borders or rules *)
    ; helper_attr : A.t
          (** style for helpful ui elements like scrollbar structures or help
              text *)
    ; user_feedback_attr : A.t
          (** style for user feedback like message count, or scrollbar position *)
    ; debug_feedback_attr : A.t
          (** style for debug feedback like the current cursor position *)
    }

  type ui_state =
    { mutable user_feedback : User_message.Style.t Pp.t option
    ; mutable debug : bool
    ; mutable reset_count : int
    ; mutable help_screen : bool
    ; mutable proc_screen : bool
    ; processes : (Pid.t, Dune_console.Process_info.t) Table.t
    ; finished_processes : (Pid.t, Dune_console.Process_info.t) Table.t
    ; recently_finished_processes : Dune_console.Process_info.t Queue.t
    ; mutable long_proc_names : bool
    ; mutable hscroll_pos : float
    ; mutable vscroll_pos : float
    ; mutable hscroll_speed : float
    ; mutable vscroll_speed : float
    ; mutable hscroll_grabbed : bool
    ; mutable vscroll_grabbed : bool
    ; mutable hscroll_enabled : bool
    ; mutable vscroll_enabled : bool
    ; hscroll_nib_size : int
    ; vscroll_nib_size : int
    ; ui_attrs : ui_attrs
    }

  let ui_state =
    { user_feedback = None
    ; debug = false
    ; reset_count = 0
    ; help_screen = false
    ; proc_screen = false
    ; processes = Table.create (module Pid) 64 (* good size? *)
    ; finished_processes = Table.create (module Pid) 4096
    ; recently_finished_processes = Queue.create ()
    ; long_proc_names = false
    ; hscroll_pos = 0.
    ; vscroll_pos = 0.
    ; hscroll_speed = 0.1
    ; vscroll_speed = 0.1
    ; hscroll_grabbed = false
    ; vscroll_grabbed = false
    ; hscroll_enabled = false
    ; vscroll_enabled = false
    ; hscroll_nib_size = 3
    ; vscroll_nib_size = 2
    ; ui_attrs =
        { divider_attr = A.(fg red)
        ; helper_attr = A.(fg yellow)
        ; user_feedback_attr = A.(fg cyan)
        ; debug_feedback_attr = A.(fg lightmagenta)
        }
    }

  let debug_image () =
    let { user_feedback
        ; debug = _
        ; reset_count
        ; help_screen
        ; proc_screen
        ; processes
        ; finished_processes
        ; recently_finished_processes = _
        ; long_proc_names
        ; hscroll_pos
        ; vscroll_pos
        ; hscroll_speed
        ; vscroll_speed
        ; hscroll_grabbed
        ; vscroll_grabbed
        ; hscroll_enabled
        ; vscroll_enabled
        ; hscroll_nib_size = _
        ; vscroll_nib_size = _
        ; ui_attrs
        } =
      ui_state
    in
    let attr = ui_attrs.debug_feedback_attr in

    [ (Term.size term |> fun (x, y) -> sprintf "Term size: (%d,%d)" x y)
    ; (reset_count |> string_of_int |> fun x -> "Reset count: " ^ x)
    ; (help_screen |> string_of_bool |> fun x -> "Help screen: " ^ x)
    ; (proc_screen |> string_of_bool |> fun x -> "Proc screen: " ^ x)
    ; ( processes |> Table.length |> string_of_int |> fun x ->
        "Process count: " ^ x )
    ; ( finished_processes |> Table.length |> string_of_int |> fun x ->
        "Finished process count: " ^ x )
    ; (long_proc_names |> string_of_bool |> fun x -> "Long proc names: " ^ x)
    ; (hscroll_pos |> string_of_float |> fun x -> "Hscroll pos: " ^ x)
    ; (vscroll_pos |> string_of_float |> fun x -> "Vscroll pos: " ^ x)
    ; (hscroll_speed |> string_of_float |> fun x -> "Hscroll speed: " ^ x)
    ; (vscroll_speed |> string_of_float |> fun x -> "Vscroll speed: " ^ x)
    ; (hscroll_grabbed |> string_of_bool |> fun x -> "Hscroll grabbed: " ^ x)
    ; (vscroll_grabbed |> string_of_bool |> fun x -> "Vscroll grabbed: " ^ x)
    ; (hscroll_enabled |> string_of_bool |> fun x -> "Hscroll enabled: " ^ x)
    ; (vscroll_enabled |> string_of_bool |> fun x -> "Vscroll enabled: " ^ x)
    ]
    |> List.map ~f:(I.string attr)
    |> fun x ->
    x
    @ [ user_feedback
        |> Option.value ~default:(Pp.text "None")
        |> User_message_to_image.pp ~attr
      ]
    |> I.vcat

  let horizontal_line_with_count ~w total index =
    let status =
      I.hcat
        [ I.uchar ui_state.ui_attrs.divider_attr (Uchar.of_int 0x169c) 1 1
        ; I.string ui_state.ui_attrs.user_feedback_attr
            (string_of_int (index + 1))
        ; I.string ui_state.ui_attrs.divider_attr "/"
        ; I.string ui_state.ui_attrs.user_feedback_attr (string_of_int total)
        ; I.uchar ui_state.ui_attrs.divider_attr (Uchar.of_int 0x169B) 1 1
        ]
    in
    I.(
      hsnap ~align:`Left w status
      </> uchar ui_state.ui_attrs.divider_attr (Uchar.of_int 0x2015) w 1)

  let line_separated_message ~total index msg =
    let img = User_message_to_image.pp (User_message.pp msg) in
    I.vcat
      [ img
      ; horizontal_line_with_count total index
          ~w:(Int.max (I.width img) (fst (Term.size term)))
      ]

  let image ~status_line ~messages =
    let status =
      match (status_line : User_message.Style.t Pp.t option) with
      | None -> []
      | Some message -> List.map ~f:User_message_to_image.pp [ message ]
    in
    let messages =
      List.mapi messages
        ~f:(line_separated_message ~total:(List.length messages))
    in
    Notty.I.vcat (messages @ status)

  let border_box image =
    let w, h = I.(width image, height image) in
    let border_element ?(attr = ui_state.ui_attrs.divider_attr) ?(width = 1)
        ?(height = 1) unicode valign halign =
      I.uchar attr (Uchar.of_int unicode) width height
      |> I.vsnap ~align:valign (h + 2)
      |> I.hsnap ~align:halign (w + 2)
    in
    I.zcat
      [ border_element 0x2554 `Top `Left (* top left corner *)
      ; border_element 0x2557 `Top `Right (* top right corner *)
      ; border_element 0x255A `Bottom `Left (* bottom left corner *)
      ; border_element 0x255D `Bottom `Right (* bottom right corner *)
      ; border_element ~width:w 0x2550 `Top `Middle (* top border *)
      ; border_element ~width:w 0x2550 `Bottom `Middle (* bottom border *)
      ; border_element ~height:h 0x2551 `Middle `Left (* left border *)
      ; border_element ~height:h 0x2551 `Middle `Right (* right border *)
      ; I.pad ~l:1 ~t:1 ~r:1 ~b:1 image
      ; I.char A.empty ' ' (w + 2) (h + 2)
      ]

  let box_with_title ~title ?(title_attr = ui_state.ui_attrs.helper_attr) image
      =
    let title =
      I.(
        string title_attr title
        |> hsnap ~align:`Middle (I.width image + 2)
        |> vsnap ~align:`Top (I.height image + 2))
    in
    I.(title </> border_box image)

  let dialogue_box ~title ?(title_attr = ui_state.ui_attrs.helper_attr) ~width
      ~height image =
    let hsnap_or_leave img =
      if I.width img < width then I.hsnap ~align:`Middle width img else img
    in
    let vsnap_or_leave img =
      if I.height img < height then I.vsnap ~align:`Middle height img else img
    in
    box_with_title ~title ~title_attr image |> vsnap_or_leave |> hsnap_or_leave

  let horizontal_scroll_bar width =
    let nib =
      let l =
        int_of_float
          (ui_state.hscroll_pos
          *. float_of_int (width - ui_state.hscroll_nib_size - 2))
        + 1 (* for the button *)
      in
      I.uchar ui_state.ui_attrs.user_feedback_attr (Uchar.of_int 0x25AC)
        ui_state.hscroll_nib_size 1
      |> I.pad ~l
    in
    I.zcat
      [ nib
      ; I.uchar ui_state.ui_attrs.helper_attr (Uchar.of_int 0x25C0) 1 1
      ; I.uchar ui_state.ui_attrs.helper_attr (Uchar.of_int 0x25B6) 1 1
        |> I.hsnap ~align:`Right width
      ; I.uchar ui_state.ui_attrs.helper_attr (Uchar.of_int 0x2500) width 1
      ; I.char A.empty ' ' 1 1 |> I.hsnap ~align:`Right width
      ]

  let vertical_scroll_bar height =
    let nib =
      let t =
        int_of_float
          (ui_state.vscroll_pos
          *. float_of_int (height - ui_state.vscroll_nib_size - 2))
        + 1 (* for the button *)
      in
      I.uchar ui_state.ui_attrs.user_feedback_attr (Uchar.of_int 0x2588) 1
        ui_state.vscroll_nib_size
      |> I.pad ~t
    in
    I.zcat
      [ nib
      ; I.uchar ui_state.ui_attrs.helper_attr (Uchar.of_int 0x25B2) 1 1
      ; I.uchar ui_state.ui_attrs.helper_attr (Uchar.of_int 0x25BC) 1 1
        |> I.vsnap ~align:`Bottom height
      ; I.uchar ui_state.ui_attrs.helper_attr (Uchar.of_int 0x2502) 1 height
      ; I.char A.empty ' ' 1 1 |> I.vsnap ~align:`Bottom height
      ]

  (** [help_screen width height] draws a help screen for a terminal of given
      [width] and [height]. *)
  let help_screen width height =
    List.map
      ~f:(I.string ui_state.ui_attrs.helper_attr)
      [ "Press 'q' to quit"
      ; "Press 'h' or '?' to toggle this screen"
      ; "Navigate with the mouse or arrow keys"
      ; "Press 'd' to toggle debug mode"
      ]
    |> I.vcat
    |> fun img ->
    [ img
    ; I.string A.empty ""
    ; I.string ui_state.ui_attrs.helper_attr "🐪 Developed by the Dune team 🐪"
      |> I.hsnap ~align:`Middle (I.width img)
    ]
    |> I.vcat |> I.pad ~l:1 ~r:1 ~t:1 ~b:1
    |> dialogue_box ~title:"Help Screen" ~width ~height

  let time_image time_diff =
    let time = Unix.gmtime time_diff in
    I.string ui_state.ui_attrs.user_feedback_attr
      (sprintf "%02d:%02d:%02d.%03.0f" time.tm_hour time.tm_min time.tm_sec
         (mod_float time_diff 1e6 *. 1e3))

  let elapsed_time started_at ended_at = ended_at -. started_at |> time_image

  let process_image
      { Dune_console.Process_info.pid; started_at; ended_at; prog_str } =
    let ended_at = Option.value ~default:(Unix.gettimeofday ()) ended_at in
    let split_prog s =
      let len = String.length s in
      if len = 0 then ("", "", "")
      else
        let rec find_prog_start i =
          if i < 0 then 0
          else
            match s.[i] with
            | '\\' | '/' -> i + 1
            | _ -> find_prog_start (i - 1)
        in
        let prog_end =
          match s.[len - 1] with
          | '"' -> len - 1
          | _ -> len
        in
        let prog_start = find_prog_start (prog_end - 1) in
        let prog_end =
          match String.index_from s prog_start '.' with
          | None -> prog_end
          | Some i -> i
        in
        let before = String.take s prog_start in
        let after = String.drop s prog_end in
        let prog = String.sub s ~pos:prog_start ~len:(prog_end - prog_start) in
        (before, prog, after)
    in
    let short_prog_name_of_prog s =
      if ui_state.long_proc_names then s
      else
        let _, s, _ = split_prog s in
        s
    in
    I.hcat
      [ I.string ui_state.ui_attrs.user_feedback_attr
          (sprintf "%d " (Pid.to_int pid))
      ; elapsed_time started_at ended_at
      ; I.char A.empty ' ' 1 1
      ; I.string ui_state.ui_attrs.helper_attr
          (short_prog_name_of_prog prog_str)
      ]

  let proc_screen width height =
    [ Table.fold ui_state.processes ~init:I.empty ~f:(fun proc_info acc ->
          I.(process_image proc_info <-> acc))
    ; I.string ui_state.ui_attrs.helper_attr "Recently finished processes:"
    ; Queue.fold ui_state.recently_finished_processes ~init:I.empty
        ~f:(fun acc proc_info -> I.(process_image proc_info <-> acc))
    ; I.string ui_state.ui_attrs.helper_attr
        (sprintf "Number of finished processes: %d"
           (ui_state.finished_processes |> Table.length))
    ]
    |> I.vcat
    |> dialogue_box ~title:"Processes" ~width ~height

  let top_frame image =
    (* The top frame is our main UI element. It contains all other widgets that
       we may wish to interact with. *)
    let tw, th = Term.size term in
    let w, h = I.(width image, height image) in
    (* We do a quick calculation of the scrolling speed and update them. *)
    ui_state.hscroll_speed <- Float.max 0. (4. /. float_of_int w);
    ui_state.vscroll_speed <- Float.max 0. (2. /. float_of_int h);
    (* We work out if the scrollbars are enabled based on if the image will fit
       in the terminal *)
    ui_state.hscroll_enabled <- w > tw;
    ui_state.vscroll_enabled <- h > th;
    (* disabling scrollbars resets the position *)
    if not ui_state.hscroll_enabled then ui_state.hscroll_pos <- 0.;
    if not ui_state.vscroll_enabled then ui_state.vscroll_pos <- 0.;
    let image =
      (* if our image spills over the size of the terminal, then we crop it
         according to the scrolling position. *)
      let l, r =
        if ui_state.hscroll_enabled then
          let l =
            int_of_float (ui_state.hscroll_pos *. float_of_int (w - tw + 1))
          in
          (l, w - tw - l)
        else (0, 0)
      in
      let t, b =
        if ui_state.vscroll_enabled then
          let t =
            int_of_float (ui_state.vscroll_pos *. float_of_int (h - th + 1))
          in
          (t, h - th - t)
        else (0, 0)
      in
      I.crop ~l ~r ~t ~b image
    in
    let help_screen =
      if ui_state.help_screen then help_screen tw th else I.empty
    in
    let proc_screen =
      if ui_state.proc_screen then proc_screen tw th else I.empty
    in
    let debug_box =
      if ui_state.debug then debug_image () |> box_with_title ~title:"Debug"
      else I.empty
    in
    let vertical_scroll_bar, horizontal_scroll_bar, corner_decoration =
      (* we adjust the sizes of the scroll bars according to how many we are
         displaying *)
      match (ui_state.hscroll_enabled, ui_state.vscroll_enabled) with
      | true, true ->
        ( vertical_scroll_bar (th - 1) |> I.hsnap ~align:`Right tw
        , horizontal_scroll_bar (tw - 1) |> I.vsnap ~align:`Bottom th
        , I.uchar ui_state.ui_attrs.helper_attr (Uchar.of_int 0x253C) 1 1
          |> I.vsnap ~align:`Bottom th |> I.hsnap ~align:`Right tw )
      | true, false ->
        (I.empty, horizontal_scroll_bar tw |> I.vsnap ~align:`Bottom th, I.empty)
      | false, true ->
        (vertical_scroll_bar th |> I.hsnap ~align:`Right tw, I.empty, I.empty)
      | _ -> (I.empty, I.empty, I.empty)
    in
    I.zcat
      [ debug_box
      ; help_screen
      ; proc_screen
      ; corner_decoration
      ; vertical_scroll_bar
      ; horizontal_scroll_bar
      ; image
      ]

  let render (state : Dune_threaded_console.state) =
    let messages = Queue.to_list state.messages in
    let image = top_frame @@ image ~status_line:state.status_line ~messages in
    Term.image term image

  (* Current TUI issues
     - Ctrl-Z and then 'fg' will stop inputs from being captured.
  *)

  (** Update any local state and finish *)
  let finish_interaction () = Unix.gettimeofday ()

  (** Update any global state and finish *)
  let finish_dirty_interaction ~mutex (state : Dune_threaded_console.state) =
    Mutex.lock mutex;
    state.dirty <- true;
    Mutex.unlock mutex;
    finish_interaction ()

  let give_user_feedback ?(style = User_message.Style.Ok) message =
    ui_state.user_feedback <- Some Pp.(tag style @@ hbox @@ message)

  let handle_resize ~width ~height ~mutex state =
    give_user_feedback ~style:User_message.Style.Debug
      (Pp.textf "You have just resized to (%d, %d)!" width height);
    finish_dirty_interaction ~mutex state

  let handle_quit () =
    (* When we encounter q we make sure to quit by signaling termination. *)
    Unix.kill (Unix.getpid ()) Sys.sigterm;
    Unix.gettimeofday ()

  let handle_help ~mutex state =
    ui_state.help_screen <- not ui_state.help_screen;
    finish_dirty_interaction ~mutex state

  let handle_process_display ~mutex state =
    ui_state.proc_screen <- not ui_state.proc_screen;
    finish_dirty_interaction ~mutex state

  let handle_horizontal_scroll ~direction ~mutex state =
    if ui_state.hscroll_enabled then
      ui_state.hscroll_pos <-
        (match direction with
        | `Up -> Float.max 0. (ui_state.hscroll_pos -. ui_state.hscroll_speed)
        | `Down -> Float.min 1. (ui_state.hscroll_pos +. ui_state.hscroll_speed));
    finish_dirty_interaction ~mutex state

  let handle_vertical_scroll ~direction ~mutex state =
    if ui_state.vscroll_enabled then
      ui_state.vscroll_pos <-
        (match direction with
        | `Up -> Float.max 0. (ui_state.vscroll_pos -. ui_state.vscroll_speed)
        | `Down -> Float.min 1. (ui_state.vscroll_pos +. ui_state.vscroll_speed));
    finish_dirty_interaction ~mutex state

  let handle_debug ~mutex state =
    ui_state.debug <- not ui_state.debug;
    finish_dirty_interaction ~mutex state

  let lipsum =
    User_message.make
      [ Pp.textf "Lorem ipsum dolor sit amet, consectetur adipiscing elit."
      ; Pp.textf
          "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."
      ; Pp.textf
          "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris \
           nisi ut aliquip ex ea commodo consequat."
      ; Pp.textf
          "Duis aute irure dolor in reprehenderit in voluptate velit esse \
           cillum dolore eu fugiat nulla pariatur."
      ; Pp.textf
          "Excepteur sint occaecat cupidatat non proident, sunt in culpa qui \
           officia deserunt mollit anim id est laborum."
      ]

  let explain_mouse_event ~pos:(x, y) ~button =
    Pp.textf "You have just %s the mouse at (%d, %d) but this does nothing!"
      (match button with
      | `Left -> "left clicked"
      | `Middle -> "middle clicked"
      | `Right -> "right clicked"
      | `Scroll `Up -> "scrolled up with"
      | `Scroll `Down -> "scrolled down with")
      x y

  let handle_unknown_input ~mutex (state : Dune_threaded_console.state) event =
    match event with
    (* lorem ipsum for testing *)
    | `Key (`ASCII 'l', [ `Meta ]) ->
      Mutex.lock mutex;
      Queue.push state.messages lipsum;
      Mutex.unlock mutex;
      finish_dirty_interaction ~mutex state
    (* Unknown ascii key presses *)
    | `Key (`ASCII c, _) ->
      give_user_feedback ~style:User_message.Style.Kwd
        (Pp.textf "You have just pressed '%c' but this does nothing!" c);
      finish_dirty_interaction ~mutex state
    (* Mouse interaction *)
    | `Mouse (`Press button, pos, _) ->
      give_user_feedback ~style:User_message.Style.Kwd
        (Pp.concat
           [ explain_mouse_event ~pos ~button
           ; Pp.textf " but this does nothing!"
           ]);
      finish_dirty_interaction ~mutex state
    (* We have no more events to handle, we finish the interaction. *)
    | _ -> finish_interaction ()

  let handle_mouse_release ~mutex state =
    ui_state.vscroll_grabbed <- false;
    ui_state.hscroll_grabbed <- false;
    finish_dirty_interaction ~mutex state

  let update_hscroll_pos ~x ~width =
    ui_state.hscroll_pos <-
      Float.max 0. @@ Float.min 1.
      @@ float_of_int (x - 2) (* minus buttons *)
         /. float_of_int (width - 2 - ui_state.hscroll_nib_size)

  let update_vscroll_pos ~y ~height =
    ui_state.vscroll_pos <-
      Float.max 0. @@ Float.min 1.
      @@ float_of_int (y - 2)
         /. float_of_int (height - 2 - ui_state.vscroll_nib_size)

  let handle_horizontal_scroll_grab ~x ~width ~mutex state =
    ui_state.hscroll_grabbed <- true;
    update_hscroll_pos ~x ~width;
    finish_dirty_interaction ~mutex state

  let handle_vertical_scroll_grab ~y ~height ~mutex state =
    ui_state.vscroll_grabbed <- true;
    update_vscroll_pos ~y ~height;
    finish_dirty_interaction ~mutex state

  let handle_long_proc_names ~mutex state =
    ui_state.long_proc_names <- not ui_state.long_proc_names;
    finish_dirty_interaction ~mutex state

  let handle_mouse_press ~pos:(x, y) ~button ~mutex state =
    (* To handle mouse presses we need to workout which widget we are trying to
       interact with. At the moment there are only two scrollbars so this is
       simple enough, but in the future a more principled approach is warranted.

       Each scroll bar has 3 components that we can interact with:

       - The scroll itself, inwhich case we need to update the scrollbar
         position.

       - The up/down arrows, inwhich case we need to move the scrollbar.
    *)
    give_user_feedback ~style:User_message.Style.Kwd
      (explain_mouse_event ~pos:(x, y) ~button);
    let tw, th = Term.size term in
    match (button, ui_state.hscroll_enabled, ui_state.vscroll_enabled) with
    (* both scrollbars' hit detection, the scrollbars resize depending on how
       many there are so the hit detection has to be tweaked. *)
    | `Left, true, true -> (
      match (Int.compare x (tw - 1), Int.compare y (th - 1)) with
      (* we hit the bottom right corner which has nothing *)
      | Eq, Eq -> finish_dirty_interaction ~mutex state
      (* checking the horizontal scrollbar *)
      | Lt, Eq ->
        (* checking the left button *)
        if x = 0 then handle_horizontal_scroll ~direction:`Up ~mutex state
          (* checking the right button *)
        else if x = tw - 2 then
          handle_horizontal_scroll ~direction:`Down ~mutex state
          (* finally we must be hitting the scrollbar itself *)
        else handle_horizontal_scroll_grab ~x ~width:tw ~mutex state
      | Eq, Lt ->
        (* checking the top button *)
        if y = 0 then handle_vertical_scroll ~direction:`Up ~mutex state
          (* checking the bottom button *)
        else if y = th - 2 then
          handle_vertical_scroll ~direction:`Down ~mutex state
          (* finally we must be hitting the scrollbar itself *)
        else handle_vertical_scroll_grab ~y ~height:th ~mutex state
      | _ -> finish_dirty_interaction ~mutex state)
    (* horizontal scrollbar hit detection *)
    | `Left, true, false ->
      if y = th - 1 then
        if x = 0 then handle_horizontal_scroll ~direction:`Up ~mutex state
        else if x = tw - 1 then
          handle_horizontal_scroll ~direction:`Down ~mutex state
        else handle_horizontal_scroll_grab ~x ~width:tw ~mutex state
      else finish_dirty_interaction ~mutex state
    (* vertical scrollbar hit detection *)
    | `Left, false, true ->
      if x = tw - 1 then
        if y = 0 then handle_vertical_scroll ~direction:`Up ~mutex state
        else if y = th - 1 then
          handle_vertical_scroll ~direction:`Down ~mutex state
        else handle_vertical_scroll_grab ~y ~height:th ~mutex state
      else finish_dirty_interaction ~mutex state
    (* no scrollbar was clicked *)
    | _ -> finish_dirty_interaction ~mutex state

  let handle_mouse_drag ~pos:(x, y) ~mutex state =
    (* todo: report event *)
    let tw, th = Term.size term in
    if ui_state.vscroll_grabbed then update_vscroll_pos ~y ~height:th
    else if ui_state.hscroll_grabbed then update_hscroll_pos ~x ~width:tw;
    finish_dirty_interaction ~mutex state

  let rec handle_user_events ~now ~time_budget ~mutex
      (state : Dune_threaded_console.state) =
    (* We check for any user input and handle it. If we go over the
       [time_budget] we give up and continue. *)
    let input_fds =
      match Unix.select [ Unix.stdin ] [] [] time_budget with
      | [], _, _ -> `Timeout
      | _ :: _, _, _ -> `Event
      | exception Unix.Unix_error (EINTR, _, _) -> `Event
    in
    match input_fds with
    | `Timeout ->
      now +. time_budget
      (* Nothing to do, we return the time at the end of the time budget. *)
    | `Event -> (
      match Term.event term with
      (* quit *)
      | `Key (`ASCII 'q', _) -> handle_quit ()
      (* toggle help screen *)
      | `Key (`ASCII ('h' | '?'), _) -> handle_help ~mutex state
      (* toggle process display *)
      | `Key (`ASCII 'p', []) -> handle_process_display ~mutex state
      (* toggle debug info *)
      | `Key (`ASCII 'd', []) -> handle_debug ~mutex state
      (* toggle long process names *)
      | `Key (`ASCII 'l', []) -> handle_long_proc_names ~mutex state
      (* on resize we wish to redraw so the state is set to dirty *)
      | `Resize (width, height) -> handle_resize ~width ~height ~mutex state
      (* when the mouse is scrolled we scroll the vertical scrollbar *)
      | `Mouse (`Press (`Scroll direction), _, []) ->
        handle_vertical_scroll ~direction ~mutex state
      (* when the mouse is alt scrolled we scroll the horizontal scrollbar *)
      | `Mouse (`Press (`Scroll direction), _, [ `Meta ]) ->
        handle_horizontal_scroll ~direction ~mutex state
      (* arrow keys and partial vim bindings can also scroll *)
      | `Key ((`Arrow `Up | `ASCII 'k'), _) ->
        handle_vertical_scroll ~direction:`Up ~mutex state
      | `Key ((`Arrow `Down | `ASCII 'j'), _) ->
        handle_vertical_scroll ~direction:`Down ~mutex state
      | `Key (`Arrow `Left, _) ->
        handle_horizontal_scroll ~direction:`Up ~mutex state
      | `Key (`Arrow `Right, _) ->
        handle_horizontal_scroll ~direction:`Down ~mutex state
      (* when the mouse is pressed we update our state *)
      | `Mouse (`Press button, pos, _) ->
        handle_mouse_press ~pos ~button ~mutex state
      (* when the mouse is dragged we update our state *)
      | `Mouse (`Drag, pos, _) -> handle_mouse_drag ~pos ~mutex state
      (* when the mouse is released we update our state *)
      | `Mouse (`Release, _, _) -> handle_mouse_release ~mutex state
      (* Finally, given an unknown event, we try to handle it with nice user
         feedback if we can make sense of it and do nothing otherwise. *)
      | _ as event -> handle_unknown_input ~mutex state event
      | exception Unix.Unix_error ((EAGAIN | EWOULDBLOCK), _, _) ->
        (* If we encounter an exception, we make sure to rehandle user events
           with a corrected time budget. *)
        let old_now = now in
        let now = Unix.gettimeofday () in
        let delta_now = now -. old_now in
        let time_budget = Float.max 0. (time_budget -. delta_now) in
        handle_user_events ~now ~time_budget ~mutex state)

  let reset () =
    ui_state.reset_count <- ui_state.reset_count + 1;
    ()

  let reset_flush_history () = ()

  let finish () =
    Notty_unix.Term.release term;
    Unix.clear_nonblock term_input_fds

  module Process = struct
    let report_start (t : Dune_console.Process_info.t) =
      Table.add_exn ui_state.processes t.pid t

    let proc_info_of (x : Proc.Process_info.t) : Dune_console.Process_info.t =
      let old_proc_info = Table.find_exn ui_state.processes x.pid in
      { old_proc_info with ended_at = Some x.end_time }

    let report_end (process_info : Proc.Process_info.t) =
      let proc_info = proc_info_of process_info in
      Table.remove ui_state.processes process_info.pid;
      Table.add_exn ui_state.finished_processes process_info.pid proc_info;
      Queue.push ui_state.recently_finished_processes proc_info;
      if
        Queue.length ui_state.recently_finished_processes > 4
        (* TODO we don't have access to concurrency info due to dune_config_file
           depending on this file. We should update this hard coded limit to the
           number of jobs *)
      then ignore (Queue.pop ui_state.recently_finished_processes)
  end
end

let backend =
  let t = lazy (Dune_threaded_console.make (module Tui ())) in
  fun () -> Lazy.force t
