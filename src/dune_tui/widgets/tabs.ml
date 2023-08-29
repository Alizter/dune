open Import
open Lwd.O

module Tab = struct
  type t =
    { title : string
    ; ui : unit -> Ui.t Lwd.t
    }
end

type t =
  { ui : Ui.t
  ; title_attr : A.t
  ; set_index : int -> unit
  }

let current_index = Lwd.var 0

let make ~title_attr (tabs : Tab.t list) =
  match tabs with
  | [] -> Code_error.raise "Tabs.make: tabs list must be non-empty." []
  | _ ->
    let+ ui =
      let* index = Lwd.get current_index in
      let { Tab.ui = current_tab; _ } =
        match List.nth tabs index with
        | Some tab -> tab
        | None ->
          Lwd.set current_index 0;
          List.nth_exn tabs index
      in
      let tabs_bar =
        tabs
        |> List.mapi ~f:(fun i { Tab.title; ui = _ } ->
          (* todo selection *)
          let tab =
            let title_attr hexrgb =
              A.(
                title_attr
                ++ bg (Drawing.attr_of_ansi_color_rgb24 (Ansi_color.RGB24.of_int hexrgb)))
            in
            if i = index
            then Ui.atom @@ I.string (title_attr 0x555555) (sprintf "[%s]" title)
            else Ui.atom @@ I.string (title_attr 0x333333) (sprintf " %s " title)
          in
          Ui.mouse_area
            (fun ~x:_ ~y:_ -> function
              | `Left ->
                Lwd.set current_index i;
                `Handled
              | _ -> `Unhandled)
            tab)
        |> Ui.hcat
      in
      let keyboard_handler = function
        | `Tab, [] ->
          Lwd.set current_index ((Lwd.peek current_index + 1) mod List.length tabs);
          `Handled
        | `Tab, [ `Shift ] ->
          Lwd.set
            current_index
            (let i = Lwd.peek current_index in
             if i = 0 then List.length tabs - 1 else i - 1);
          `Handled
        | _ -> `Unhandled
      in
      current_tab () >>| Ui.join_y tabs_bar >>| Ui.keyboard_area keyboard_handler
    in
    let set_index i = if i < List.length tabs && i >= 0 then Lwd.set current_index i in
    { ui; title_attr; set_index }
;;
