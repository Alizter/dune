open Import

val term_size : (int * int) Lwd.var
val helper_attr : A.t Lwd.var
val divider_attr : A.t Lwd.var
val extra_tabs : Tabs.Tab.t list Lwd.var

(** A backend that uses Notty to display the status line in the terminal. *)
val backend : unit -> Dune_console.Backend.t

module Widgets : sig
  module Button : module type of Button
  module Tabs : module type of Tabs
end

module Drawing : module type of Drawing
module Import = Import
