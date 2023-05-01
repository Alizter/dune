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

let image_of_user_message_style_pp =
  Notty.I.strf "%a@."
    (Pp.to_fmt_with_tags ~tag_handler:attr_of_user_message_style)

module Tui () = struct
  module Term = Notty_unix.Term

  let term = Term.create ~nosig:false ()

  let start () = Unix.set_nonblock Unix.stdin

  let user_feedback = ref None

  let reset_count = ref 0

  let help_screen = ref false

  let horizontal_line_with_count total index =
    let module A = Notty.A in
    let module I = Notty.I in
    let twidth, _ = Term.size term in
    let status =
      let left = I.uchar A.(fg red) (Uchar.of_int 0x169c) 1 1 in
      let index = I.string A.(fg blue) (string_of_int (index + 1)) in
      let mid = I.string A.(fg red) "/" in
      let total = I.string A.(fg blue) (string_of_int total) in
      let right = I.uchar A.(fg red) (Uchar.of_int 0x169B) 1 1 in
      I.(left <|> index <|> mid <|> total <|> right)
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
      @@ Pp.textf "Reset count %d" !reset_count
    in
    Notty.I.vcat
      (messages @ status
      @ List.map ~f:image_of_user_message_style_pp
          (Option.to_list !user_feedback)
      @ [ reset_count ])

  let top_frame image =
    let module A = Notty.A in
    let module I = Notty.I in
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
      if !help_screen then
        let help_screen =
          Pp.tag User_message.Style.Kwd
          @@ Pp.vbox
          @@ Pp.concat ~sep:Pp.newline
               [ Pp.hbox @@ Pp.text "Help screen"
               ; Pp.hbox @@ Pp.text "Press 'q' to quit"
               ; Pp.hbox @@ Pp.text "Press 'h' to toggle this screen"
               ]
        in
        image_of_user_message_style_pp help_screen
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
     - Resizing from full screen to a small size will not update the screen
       causing it not to be drawn.
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
    user_feedback := Some Pp.(tag style @@ hbox @@ message)

  let resize ~width ~height ~mutex (state : Dune_threaded_console.state) =
    give_user_feedback ~style:User_message.Style.Debug
      (Pp.textf "You have just resized to (%d, %d)!" width height);
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
      (* TODO if anything fancy is done in the UI in the future we need to lock
         the state with the provided mutex *)
      match Term.event term with
      (* quit when sure *)
      | `Key (`ASCII 'q', _) ->
        (* When we encounter q we make sure to quit by signaling termination. *)
        Unix.kill (Unix.getpid ()) Sys.sigterm;
        Unix.gettimeofday ()
      (* toggle help screen *)
      | `Key (`ASCII 'h', _) ->
        help_screen := not !help_screen;
        finish_dirty_interaction ~mutex state
      (* on resize we wish to redraw so the state is set to dirty *)
      | `Resize (width, height) -> resize ~width ~height ~mutex state
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
      | _ -> finish_interaction ()
      | exception Unix.Unix_error ((EAGAIN | EWOULDBLOCK), _, _) ->
        (* If we encounter an exception, we make sure to rehandle user events
           with a corrected time budget. *)
        let old_now = now in
        let now = Unix.gettimeofday () in
        let delta_now = now -. old_now in
        let time_budget = Float.max 0. (time_budget -. delta_now) in
        handle_user_events ~now ~time_budget ~mutex state)

  let reset () =
    reset_count := !reset_count + 1;
    ()

  let reset_flush_history () = ()

  let finish () =
    Notty_unix.Term.release term;
    Unix.clear_nonblock Unix.stdin
end

let backend =
  let t = lazy (Dune_threaded_console.make (module Tui ())) in
  fun () -> Lazy.force t
