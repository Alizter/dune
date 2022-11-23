open Import

type t =
  | Bool of bool
  | String of string
  | Number of [ `I of int | `F of float ]
  | Path of string
  | List of t list
  | Attr of bool * entry list
  | Let of entry list * t
  | If_then_else of t * t * t
  | Function of
      [ `Pattern of string
      | `SetPattern of
        string option * [ `A of string | `O of string * t ] list * bool
      ]
      * t
  | FunctionApp of t * t
  | Assert of t * t
  | With of t * t

and entry =
  | Inherit of string list
  | Inherit_from_scope of string * string list
  | Declare of string * t

let inline_data ?inherit_ ?inherit_from_scope data =
  List.concat
    [ (match inherit_ with
      | Some inherit_ -> List.map inherit_ ~f:(fun var -> Inherit [ var ])
      | None -> [])
    ; (match inherit_from_scope with
      | Some (scope, vars) ->
        List.map vars ~f:(fun var -> Inherit_from_scope (scope, [ var ]))
      | None -> [])
    ; List.map data ~f:(fun (var, value) -> Declare (var, value))
    ]

let attr ?(rec_ = false) ?inherit_ ?inherit_from_scope data =
  Attr (rec_, inline_data ?inherit_ ?inherit_from_scope data)

let let_ ?inherit_ ?inherit_from_scope data t =
  Let (inline_data ?inherit_ ?inherit_from_scope data, t)

let bool b = Bool b

let string s = String s

let int i = Number (`I i)

let float f = Number (`F f)

let path s = Path s

let list l = List l

let if_then_else b x y = If_then_else (b, x, y)

let fun_ var t = Function (`Pattern var, t)

let fun_set ?at vars ?(ellipsis = false) t =
  Function (`SetPattern (at, vars, ellipsis), t)

let fun_app f x = FunctionApp (f, x)

let assert_ b t = Assert (b, t)

let with_ s t = With (s, t)

let pp_wrapped ~indent ~left ~right ~sep ~pp l =
  let open Pp.O in
  Pp.box ~indent
    (Pp.verbatim left ++ Pp.space ++ Pp.hvbox (Pp.concat_map l ~sep ~f:pp))
  ++ Pp.space ++ Pp.verbatim right

let pp_data ~indent ~left ~right ~pp l =
  let open Pp.O in
  let pp = function
    | Inherit l ->
      Pp.verbatim "inherit" ++ Pp.space
      ++ Pp.concat_map ~sep:Pp.space ~f:Pp.verbatim l
      ++ Pp.text ";"
    | Inherit_from_scope (s, l) ->
      Pp.verbatim "inherit" ++ Pp.space
      ++ Pp.verbatim ("(" ^ s ^ ")")
      ++ Pp.concat_map ~sep:Pp.space ~f:Pp.verbatim l
      ++ Pp.text ";"
    | Declare (s, v) -> pp (s, v)
  in
  pp_wrapped ~indent ~left ~right ~sep:Pp.space ~pp l

let pp_equals_semicolon ~pp (k, v) =
  Pp.hvbox @@ Pp.concat [ Pp.verbatim @@ sprintf "%s = " k; pp v; Pp.text ";" ]

let rec pp ~indent =
  let open Pp.O in
  function
  | Bool b -> Pp.verbatim (string_of_bool b)
  | String s -> Pp.verbatim ("\"" ^ s ^ "\"")
  | Number (`I i) -> Pp.text @@ Int.to_string i
  | Number (`F f) -> Pp.text @@ Float.to_string f
  | Path p -> Pp.verbatim p
  | List l ->
    pp_wrapped ~indent ~left:"[" ~right:"]" ~sep:Pp.space ~pp:(pp ~indent) l
  | Attr (rec_, data) ->
    let left = if rec_ then "rec {" else "{" in
    pp_data ~indent ~left ~right:"}" data
      ~pp:(pp_equals_semicolon ~pp:(pp ~indent))
  | Let (bindings, body) ->
    pp_data ~indent ~left:"let" ~right:"in" bindings
      ~pp:(pp_equals_semicolon ~pp:(pp ~indent))
    ++ Pp.space ++ pp ~indent body
  | If_then_else (b, x, y) ->
    (* TODO this doesn't print quite right *)
    (Pp.hvbox ~indent
    @@ (Pp.verbatim "if" ++ Pp.space ++ pp ~indent b ++ Pp.space))
    ++ (Pp.vbox ~indent
       @@ (Pp.verbatim "then" ++ Pp.space ++ pp ~indent x ++ Pp.space))
    ++ (Pp.vbox ~indent @@ (Pp.verbatim "else" ++ Pp.space ++ pp ~indent y))
  | Function (`Pattern p, body) ->
    Pp.box (Pp.verbatim p ++ Pp.char ':' ++ Pp.space ++ pp ~indent body)
  | Function (`SetPattern (at, p, b), body) ->
    let pp_var =
      let pp = function
        | `A s -> Pp.verbatim s
        | `O (s, t) ->
          Pp.verbatim s ++ Pp.space ++ Pp.char '?' ++ Pp.space ++ pp ~indent t
      in
      let pp = function
        | `Ellipsis -> Pp.verbatim "..."
        | `Var v -> pp v
      in
      pp_wrapped ~indent ~left:"{" ~right:"}" ~sep:(Pp.char ',' ++ Pp.space) ~pp
    in
    let p = List.map ~f:(fun x -> `Var x) p @ if b then [ `Ellipsis ] else [] in
    let at =
      match at with
      | Some at -> Pp.char '@' ++ Pp.verbatim at
      | None -> Pp.nop
    in
    Pp.box (pp_var p ++ at ++ Pp.char ':' ++ Pp.space ++ pp ~indent body)
  | FunctionApp (f, x) ->
    Pp.box
      (pp ~indent f ++ Pp.space
      ++ pp_wrapped ~indent ~left:"(" ~right:")" ~sep:Pp.nop ~pp:(pp ~indent)
           [ x ])
  | Assert (b, t) ->
    Pp.box
      (Pp.verbatim "assert" ++ Pp.space ++ pp ~indent b ++ Pp.char ';'
     ++ Pp.space ++ pp ~indent t)
  | With (s, t) ->
    Pp.verbatim "with" ++ Pp.space ++ pp ~indent s ++ Pp.char ';' ++ Pp.space
    ++ pp ~indent t

let pp ?(indent = 2) t = pp ~indent t

let rec to_dyn = function
  | Bool b -> Dyn.Bool b
  | String s -> Dyn.variant "String" [ Dyn.String s ]
  | Number (`I i) -> Dyn.variant "Number" [ Dyn.Int i ]
  | Number (`F f) -> Dyn.variant "Number" [ Dyn.Float f ]
  | Path s -> Dyn.variant "Path" [ Dyn.String s ]
  | List l -> Dyn.variant "List" [ Dyn.List (List.map l ~f:to_dyn) ]
  | Attr (rec_, data) ->
    Dyn.variant "Attr" [ Dyn.Bool rec_; Dyn.list (to_dyn_entry ~to_dyn) data ]
  | Let (bindings, body) ->
    Dyn.variant "Let" [ Dyn.list (to_dyn_entry ~to_dyn) bindings; to_dyn body ]
  | If_then_else (b, x, y) ->
    Dyn.variant "If_then_else" [ to_dyn b; to_dyn x; to_dyn y ]
  | Function (`Pattern p, body) ->
    Dyn.variant "Function" [ Dyn.String p; to_dyn body ]
  | Function (`SetPattern (at, p, b), body) ->
    let to_dyn_var = function
      | `A s -> Dyn.variant "A" [ Dyn.String s ]
      | `O (s, t) -> Dyn.variant "O" [ Dyn.String s; to_dyn t ]
    in
    Dyn.variant "Function"
      [ Dyn.Option (Option.map at ~f:Dyn.string)
      ; Dyn.List (List.map p ~f:to_dyn_var)
      ; Dyn.Bool b
      ; to_dyn body
      ]
  | FunctionApp (f, x) -> Dyn.variant "FunctionApp" [ to_dyn f; to_dyn x ]
  | Assert (b, t) -> Dyn.variant "Assert" [ to_dyn b; to_dyn t ]
  | With (s, t) -> Dyn.variant "With" [ to_dyn s; to_dyn t ]

and to_dyn_entry ~to_dyn = function
  | Inherit l -> Dyn.List (List.map l ~f:Dyn.string)
  | Inherit_from_scope (s, l) ->
    Dyn.List (Dyn.String s :: List.map l ~f:Dyn.string)
  | Declare (s, a) -> Dyn.Tuple [ Dyn.String s; to_dyn a ]
