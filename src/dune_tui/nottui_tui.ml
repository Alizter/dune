open Stdune

let attr_of_ansi_color_style (s : Ansi_color.Style.t) =
  let open Notty in
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
  | `Bold -> A.(st bold)
  | `Italic -> A.(st italic)
  | `Dim -> A.(st dim)
  | `Underline -> A.(st underline)

let attr_of_user_message_style fmt t (pp : User_message.Style.t Pp.t) : unit =
  let attr =
    let open Notty in
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

open Nottui
module W = Nottui_widgets

type tree = Tree of string * (unit -> tree list)

let rec tree_ui (Tree (label, child)) =
  let opened = Lwd.var false in
  let render is_opened =
    let btn_text = if is_opened then "[-] " else "[+] " in
    let btn_action () = Lwd.set opened (not is_opened) in
    let btn = W.button (btn_text ^ label) btn_action in
    let layout node forest = Ui.join_y node (Ui.join_x (Ui.space 2 0) forest) in
    if is_opened then Lwd.map ~f:(layout btn) (forest_ui (child ()))
    else Lwd.pure btn
  in
  Lwd.join (Lwd.map ~f:render (Lwd.get opened))

and forest_ui nodes = Lwd_utils.pack Ui.pack_y (List.map ~f:tree_ui nodes)

module Tui () = struct
  module Term = Notty_unix.Term

  let term = Term.create ~nosig:false ()

  let renderer = Renderer.make ()

  let start () = Unix.set_nonblock Unix.stdin

  let image ~status_line ~messages =
    let status =
      match (status_line : User_message.Style.t Pp.t option) with
      | None -> []
      | Some message -> [ image_of_user_message_style_pp message ]
    in
    let messages =
      List.map messages ~f:(fun msg ->
          image_of_user_message_style_pp (User_message.pp msg))
    in
    Notty.I.vcat (messages @ status)

  let rec fake_fs () =
    [ Tree ("bin", fake_fs); Tree ("home", fake_fs); Tree ("usr", fake_fs) ]
  

  let render (state : Dune_console.Threaded.state) =
    let messages = Queue.to_list state.messages in
    let image = image ~status_line:state.status_line ~messages in
    let root = Lwd.observe (forest_ui (fake_fs ())) in
    Ui_loop.step ~process_event:false ~renderer term root;
    Term.image term image

  let handle_user_events ~now ~time_budget mutex =
    let input_fds, _, _ = Unix.select [ Unix.stdin ] [] [] time_budget in
    match input_fds with
    | [] -> now +. time_budget
    | _ :: _ ->
      Mutex.lock mutex;
      (try
         match Term.event term with
         | `Key (`ASCII 'q', _) -> Unix.kill (Unix.getpid ()) Sys.sigterm
         | _ -> ()
       with Unix.Unix_error ((EAGAIN | EWOULDBLOCK), _, _) -> ());
      Mutex.unlock mutex;
      Unix.gettimeofday ()

  let reset () = ()

  let reset_flush_history () = ()

  let finish () = Notty_unix.Term.release term
end

let backend =
  let t = lazy (Dune_console.Threaded.make (module Tui ())) in
  fun () -> Lazy.force t
