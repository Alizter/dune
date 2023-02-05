open Stdune

module No_flush = struct
  let status_line = ref Pp.nop

  let start () = ()

  let status_line_len = ref 0

  let hide_status_line () =
    if !status_line_len > 0 then Printf.eprintf "\r%*s\r" !status_line_len ""

  let show_status_line () =
    if !status_line_len > 0 then Ansi_color.prerr !status_line

  let set_status_line = function
    | None ->
      hide_status_line ();
      status_line := Pp.nop;
      status_line_len := 0
    | Some line ->
      let line = Pp.map_tags line ~f:User_message.Print_config.default in
      let line_len = String.length (Format.asprintf "%a" Pp.to_fmt line) in
      hide_status_line ();
      status_line := line;
      status_line_len := line_len;
      show_status_line ()

  let print_if_no_status_line _msg = ()

  let print_user_message msg =
    hide_status_line ();
    Dumb.No_flush.print_user_message msg;
    show_status_line ()

  let reset () = Dumb.reset ()

  let finish () = set_status_line None

  let reset_flush_history () = Dumb.reset_flush_history ()
end

let unthreaded = Combinators.flush (module No_flush : Backend_intf.S)

let threaded () =
  Threaded.make
    (module struct
      include No_flush

      let render (state : Threaded_intf.state) =
        while not (Queue.is_empty state.messages) do
          print_user_message (Queue.pop_exn state.messages)
        done;
        set_status_line state.status_line;
        flush stderr

      (* The current console doesn't react to user events so we just sleep until
          the next loop iteration. Because it doesn't react to user input, it cannot
          modify the UI state, and as a consequence doesn't need the mutex. *)
      let handle_user_events ~now ~time_budget _ =
        Unix.sleepf time_budget;
        now +. time_budget
    end)
