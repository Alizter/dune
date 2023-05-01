open Stdune

let attr_of_ansi_color_rgb8 (c : Ansi_color.RGB8.t) =
  let module A = Notty.A in
  match Ansi_color.RGB8.to_int c with
  | 0 -> A.black
  | 1 -> A.red
  | 2 -> A.green
  | 3 -> A.yellow
  | 4 -> A.blue
  | 5 -> A.magenta
  | 6 -> A.cyan
  | 7 -> A.white
  | 8 -> A.lightblack
  | 9 -> A.lightred
  | 10 -> A.lightgreen
  | 11 -> A.lightyellow
  | 12 -> A.lightblue
  | 13 -> A.lightmagenta
  | 14 -> A.lightcyan
  | 15 -> A.lightwhite
  | i when i <= 231 ->
    let i = i - 16 in
    let r = i / 36 in
    let g = i / 6 mod 6 in
    let b = i mod 6 in
    A.rgb ~r ~g ~b
  | i when i <= 255 -> A.gray (i - 232)
  | i -> Code_error.raise "invalid 8-bit color" [ ("value", Dyn.int i) ]

let attr_of_ansi_color_rgb24 (c : Ansi_color.RGB24.t) =
  let module A = Notty.A in
  A.rgb ~r:(Ansi_color.RGB24.red c) ~g:(Ansi_color.RGB24.green c)
    ~b:(Ansi_color.RGB24.blue c)

let attr_of_ansi_color_style (s : Ansi_color.Style.t) =
  let module A = Notty.A in
  match s with
  | `Fg_black -> A.(fg black)
  | `Fg_red -> A.(fg red)
  | `Fg_green -> A.(fg green)
  | `Fg_yellow -> A.(fg yellow)
  | `Fg_blue -> A.(fg blue)
  | `Fg_magenta -> A.(fg magenta)
  | `Fg_cyan -> A.(fg cyan)
  | `Fg_white -> A.(fg white)
  | `Fg_default -> A.empty
  | `Fg_bright_black -> A.(fg lightblack)
  | `Fg_bright_red -> A.(fg lightred)
  | `Fg_bright_green -> A.(fg lightgreen)
  | `Fg_bright_yellow -> A.(fg lightyellow)
  | `Fg_bright_blue -> A.(fg lightblue)
  | `Fg_bright_magenta -> A.(fg lightmagenta)
  | `Fg_bright_cyan -> A.(fg lightcyan)
  | `Fg_bright_white -> A.(fg lightwhite)
  | `Fg_8_bit_color c -> A.fg (attr_of_ansi_color_rgb8 c)
  | `Fg_24_bit_color c -> A.fg (attr_of_ansi_color_rgb24 c)
  | `Bg_black -> A.(bg black)
  | `Bg_red -> A.(bg red)
  | `Bg_green -> A.(bg green)
  | `Bg_yellow -> A.(bg yellow)
  | `Bg_blue -> A.(bg blue)
  | `Bg_magenta -> A.(bg magenta)
  | `Bg_cyan -> A.(bg cyan)
  | `Bg_white -> A.(bg white)
  | `Bg_default -> A.empty
  | `Bg_bright_black -> A.(bg lightblack)
  | `Bg_bright_red -> A.(bg lightred)
  | `Bg_bright_green -> A.(bg lightgreen)
  | `Bg_bright_yellow -> A.(bg lightyellow)
  | `Bg_bright_blue -> A.(bg lightblue)
  | `Bg_bright_magenta -> A.(bg lightmagenta)
  | `Bg_bright_cyan -> A.(bg lightcyan)
  | `Bg_bright_white -> A.(bg lightwhite)
  | `Bg_8_bit_color c -> A.bg (attr_of_ansi_color_rgb8 c)
  | `Bg_24_bit_color c -> A.bg (attr_of_ansi_color_rgb24 c)
  | `Bold -> A.(st bold)
  | `Italic -> A.(st italic)
  | `Dim -> A.(st dim)
  | `Underline -> A.(st underline)

let attr_of_user_message_style fmt t (pp : User_message.Style.t Pp.t) : unit =
  let attr =
    let module A = Notty.A in
    match (t : User_message.Style.t) with
    | Loc -> A.(st bold)
    | Error -> A.(st bold ++ fg red)
    | Warning -> A.(st bold ++ fg magenta)
    | Kwd -> A.(st bold ++ fg blue)
    | Id -> A.(st bold ++ fg yellow)
    | Prompt -> A.(st bold ++ fg green)
    | Hint -> A.(st italic ++ fg white)
    | Details -> A.(st dim ++ fg white)
    | Ok -> A.(st italic ++ fg green)
    | Debug -> A.(st underline ++ fg lightcyan)
    | Success -> A.(st bold ++ fg green)
    | Ansi_styles l ->
      List.fold_left ~init:A.empty l ~f:(fun attr s ->
          A.(attr ++ attr_of_ansi_color_style s))
  in
  Notty.I.pp_attr attr Pp.to_fmt fmt pp

let image_of_user_message_style_pp ?attr =
  Notty.I.strf ?attr "%a@."
    (Pp.to_fmt_with_tags ~tag_handler:attr_of_user_message_style)

module Tui () = struct
  module Term = Notty_unix.Term
  module A = Notty.A
  module I = Notty.I

  let term = Term.create ~nosig:false ()

  let start () = Unix.set_nonblock Unix.stdin

  type ui_state =
    { mutable user_feedback : User_message.Style.t Pp.t option
    ; mutable reset_count : int
    ; mutable help_screen : bool
    }

  let ui_state = { user_feedback = None; reset_count = 0; help_screen = false }

  let horizontal_line_with_count total index =
    let twidth, _ = Term.size term in
    let status =
      I.hcat
        [ I.uchar A.(fg red) (Uchar.of_int 0x169c) 1 1
        ; I.string A.(fg blue) (string_of_int (index + 1))
        ; I.string A.(fg red) "/"
        ; I.string A.(fg blue) (string_of_int total)
        ; I.uchar A.(fg red) (Uchar.of_int 0x169B) 1 1
        ]
    in
    I.(
      hsnap ~align:`Left twidth status
      </> uchar A.(fg red) (Uchar.of_int 0x2015) twidth 1)

  let line_separated_message ~total index msg =
    Notty.I.(
      image_of_user_message_style_pp (User_message.pp msg)
      <-> horizontal_line_with_count total index)

  let image ~status_line ~messages =
    let status =
      match (status_line : User_message.Style.t Pp.t option) with
      | None -> []
      | Some message -> List.map ~f:image_of_user_message_style_pp [ message ]
    in
    let messages =
      List.mapi messages
        ~f:(line_separated_message ~total:(List.length messages))
    in
    let reset_count =
      image_of_user_message_style_pp
      @@ Pp.tag User_message.Style.Debug
      @@ Pp.hbox
      @@ Pp.textf "Reset count %d" ui_state.reset_count
    in
    Notty.I.vcat
      (messages @ status
      @ List.map ~f:image_of_user_message_style_pp
          (Option.to_list ui_state.user_feedback)
      @ [ reset_count ])

  let border_box image =
    let w, h = I.(width image, height image) in
    let border_element ?(attr = A.(fg red)) ?(width = 1) ?(height = 1) unicode
        valign halign =
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
      ; I.void (w + 2) (h + 2)
      ]

  let dialogue_box ~title ?(title_attr = Notty.A.(bg blue ++ fg black)) image =
    let title =
      I.(
        string title_attr title
        |> hsnap ~align:`Middle (I.width image + 2)
        |> vsnap ~align:`Top (I.height image + 2))
    in
    I.(title </> border_box image)

  let top_frame image =
    let twidth, theight = Term.size term in
    (* We need to determine whether or not we need to add a scroll bar *)
    let vertical_scroll_bar =
      I.hsnap ~align:`Right twidth
      @@
      if I.height image > theight then
        I.(uchar A.(fg white) (Uchar.of_int 0x2591) 1 theight)
      else I.empty
    in
    let horizontal_scroll_bar =
      I.vsnap ~align:`Bottom theight
      @@
      if I.width image > twidth then
        I.(uchar A.(fg white) (Uchar.of_int 0x2591) twidth 1)
      else I.empty
    in
    let help_screen =
      if ui_state.help_screen then
        let attr = A.(fg yellow) in
        List.map ~f:(I.string attr)
          [ "Press 'q' to quit"
          ; "Press 'h' to toggle this screen"
          ; ""
          ; "🐪 Developed by the Dune team 🐪"
          ]
        |> I.vcat |> I.pad ~l:1 ~r:1 ~t:1 ~b:1
        |> dialogue_box ~title:"Help Screen" ~title_attr:A.(fg yellow)
        |> I.hsnap ~align:`Middle twidth
        |> I.vsnap ~align:`Middle theight
      else I.empty
    in
    I.(help_screen </> vertical_scroll_bar </> horizontal_scroll_bar </> image)

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

  let handle_unknown_input ~mutex state event =
    match event with
    (* Unknown ascii key presses *)
    | `Key (`ASCII c, _) ->
      give_user_feedback ~style:User_message.Style.Kwd
        (Pp.textf "You have just pressed '%c' but this does nothing!" c);
      finish_dirty_interaction ~mutex state
    (* Mouse interaction *)
    | `Mouse (`Press button, (x, y), _) ->
      give_user_feedback ~style:User_message.Style.Kwd
        (Pp.textf
           "You have just %s the mouse at (%d, %d) but this does nothing!"
           (match button with
           | `Left -> "left clicked"
           | `Middle -> "middle clicked"
           | `Right -> "right clicked"
           | `Scroll `Up -> "scrolled up with"
           | `Scroll `Down -> "scrolled down with")
           x y);
      finish_dirty_interaction ~mutex state
    (* We have no more events to handle, we finish the interaction. *)
    | _ -> finish_interaction ()

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
      (* TODO if anything fancy is done in the UI in the future we need to lock
         the state with the provided mutex *)
      match Term.event term with
      (* quit *)
      | `Key (`ASCII 'q', _) -> handle_quit ()
      (* toggle help screen *)
      | `Key (`ASCII 'h', _) -> handle_help ~mutex state
      (* on resize we wish to redraw so the state is set to dirty *)
      | `Resize (width, height) -> handle_resize ~width ~height ~mutex state
      (* Finally given an unknown event, we try to handle it with nice user
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
    Unix.clear_nonblock Unix.stdin
end

let backend =
  let t = lazy (Dune_threaded_console.make (module Tui ())) in
  fun () -> Lazy.force t
