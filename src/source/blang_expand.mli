open Import

(** [eval t ~short_circuit ~dir ~f] evaluates a boolean language expression.

    When [short_circuit] is true, [and] and [or] use short-circuit evaluation:
    [and] stops at the first [false], [or] stops at the first [true]. This is
    useful when later expressions depend on earlier ones (e.g., checking
    [%{version:pkg}] only when [%{lib-available:pkg}] is true).

    When [short_circuit] is false, all sub-expressions are evaluated, which
    matches the historical behavior. *)
val eval
  :  Blang.t
  -> short_circuit:bool
  -> dir:Path.t
  -> f:Value.t list Memo.t String_with_vars.expander
  -> bool Memo.t
