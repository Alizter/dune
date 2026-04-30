module Path = struct
  type simple = string list

  type expr =
    | Simple of simple
    | Apply of
        { f : expr
        ; x : expr
        ; proj : simple option
        }
end

module Loc = struct
  type t =
    | Simple of int * int * int
    | Multiline of
        { start : int * int
        ; stop : int * int
        }
end

module Edge = struct
  type t =
    | Normal
    | Epsilon
end

type 'a located =
  { data : 'a
  ; loc : Loc.t
  }

type 'a bind =
  { name : string option
  ; expr : 'a
  }

type m2l = expression located list

and expression =
  | Open of module_expr
  | Include of module_expr
  | SigInclude of module_type
  | Bind of module_expr bind
  | Bind_sig of module_type bind
  | Bind_rec of module_expr bind list
  | Minor of minor list
  | Extension_node of extension

and minor =
  | Access of access_entry list
  | Pack of module_expr located
  | Extension_node_minor of extension located
  | Local_open of Loc.t * module_expr * minor list
  | Local_bind of Loc.t * module_expr bind * minor list
  | External of string list

and access_entry =
  { path : Path.expr
  ; loc : Loc.t
  ; edge : Edge.t
  }

and module_expr =
  | Ident of Path.simple
  | Apply of
      { f : module_expr
      ; x : module_expr
      }
  | Fun of module_expr fn
  | Constraint of module_expr * module_type
  | Str of m2l
  | Val of minor list
  | Extension_node_me of extension
  | Abstract
  | Unpacked
  | Open_me of
      { opens : Path.simple located list
      ; expr : module_expr
      }
  | Proj of
      { me : module_expr
      ; proj : Path.simple
      }

and module_type =
  | Alias of Path.simple
  | Ident_mt of Path.expr
  | Sig of m2l
  | Fun_mt of module_type fn
  | Of of module_expr
  | Extension_node_mt of extension
  | Abstract_mt
  | With of
      { body : module_type
      ; constraints : with_constraint list
      }

and with_constraint =
  { lhs : Path.simple
  ; delete : bool
  ; rhs : with_rhs
  }

and with_rhs =
  | Type of minor list
  | Module of Path.simple located
  | Module_type of module_type

and 'a fn =
  { arg : functor_arg option
  ; body : 'a
  }

and functor_arg =
  { arg_name : string option
  ; arg_signature : module_type
  }

and extension =
  { ext_name : string
  ; ext_payload : extension_core
  }

and extension_core =
  | Ext_module of m2l
  | Ext_val of minor list

(* {1 Sexp decoding using Dune_sexp.Decoder}

   We use lazy values to break the mutual recursion between parsers.
   Each parser is a [lazy 'a t] that is forced via [lz] at the point of use. *)

open Dune_sexp.Decoder

let lz (l : 'a t Lazy.t) : 'a t =
  let* () = return () in
  Lazy.force l
;;

let simple_path : Path.simple t = enter (repeat string)

let loc : Loc.t t =
  sum
    [ ( "Simple"
      , let+ l, c1, c2 = triple int int int in
        Loc.Simple (l, c1, c2) )
    ; ( "Multiline"
      , enter
          (let+ start = pair int int
           and+ stop = pair int int in
           Loc.Multiline { start; stop }) )
    ]
;;

let edge : Edge.t t = enum [ "Normal", Edge.Normal; "Epsilon", Edge.Epsilon ]

let option_string : string option t =
  sum
    [ ( "Some"
      , let+ s = string in
        Some s )
    ; "None", return None
    ]
;;

let option_simple_path : Path.simple option t =
  sum
    [ ( "Some"
      , let+ p = simple_path in
        Some p )
    ; "None", return None
    ]
;;

let rec lazy_path_expr : Path.expr t Lazy.t =
  lazy
    (sum
       [ ( "S"
         , let+ p = simple_path in
           Path.Simple p )
       ; ( "Apply"
         , enter
             (let+ f = lz lazy_path_expr
              and+ x = lz lazy_path_expr
              and+ proj = option_simple_path in
              Path.Apply { f; x; proj }) )
       ])

and lazy_module_expr : module_expr t Lazy.t =
  lazy
    (sum
       [ ( "Ident"
         , let+ p = simple_path in
           Ident p )
       ; ( "Apply"
         , enter
             (let+ f = lz lazy_module_expr
              and+ x = lz lazy_module_expr in
              Apply { f; x }) )
       ; ( "Fun"
         , enter
             (let+ arg = lz lazy_functor_arg
              and+ body = lz lazy_module_expr in
              Fun { arg; body }) )
       ; ( "Constraint"
         , enter
             (let+ me = lz lazy_module_expr
              and+ mt = lz lazy_module_type in
              Constraint (me, mt)) )
       ; ( "Str"
         , let+ m = lz lazy_m2l in
           Str m )
       ; ( "Val"
         , let+ ms = lz lazy_minors in
           Val ms )
       ; ( "Extension_node"
         , let+ e = lz lazy_extension in
           Extension_node_me e )
       ; "Abstract", return Abstract
       ; "Unpacked", return Unpacked
       ; ( "Open_me"
         , enter
             (let+ opens = enter (repeat (lz lazy_simple_path_located))
              and+ expr = lz lazy_module_expr in
              Open_me { opens; expr }) )
       ; ( "Proj"
         , enter
             (let+ me = lz lazy_module_expr
              and+ proj = simple_path in
              Proj { me; proj }) )
       ])

and lazy_module_type : module_type t Lazy.t =
  lazy
    (sum
       [ ( "Alias"
         , let+ p = simple_path in
           Alias p )
       ; ( "Ident"
         , let+ p = lz lazy_path_expr in
           Ident_mt p )
       ; ( "Sig"
         , let+ m = lz lazy_m2l in
           Sig m )
       ; ( "Fun"
         , enter
             (let+ arg = lz lazy_functor_arg
              and+ body = lz lazy_module_type in
              Fun_mt { arg; body }) )
       ; ( "Of"
         , let+ me = lz lazy_module_expr in
           Of me )
       ; ( "Extension_node"
         , let+ e = lz lazy_extension in
           Extension_node_mt e )
       ; "Abstract", return Abstract_mt
       ; ( "With"
         , enter
             (let+ body = lz lazy_module_type
              and+ constraints = enter (repeat (lz lazy_with_constraint)) in
              With { body; constraints }) )
       ])

and lazy_with_constraint : with_constraint t Lazy.t =
  lazy
    (enter
       (let+ lhs = simple_path
        and+ delete = bool
        and+ rhs = lz lazy_with_rhs in
        { lhs; delete; rhs }))

and lazy_with_rhs : with_rhs t Lazy.t =
  lazy
    (sum
       [ ( "Type"
         , let+ ms = lz lazy_minors in
           Type ms )
       ; ( "Module"
         , let+ p = lz lazy_simple_path_located in
           Module p )
       ; ( "Module_type"
         , let+ mt = lz lazy_module_type in
           Module_type mt )
       ])

and lazy_functor_arg : functor_arg option t Lazy.t =
  lazy
    (sum
       [ ( "Some"
         , enter
             (let+ arg_name = option_string
              and+ arg_signature = lz lazy_module_type in
              Some { arg_name; arg_signature }) )
       ; "None", return None
       ])

and lazy_minor : minor t Lazy.t =
  lazy
    (sum
       [ ( "Access"
         , let+ entries = enter (repeat (lz lazy_access_entry)) in
           Access entries )
       ; ( "Pack"
         , let+ me = lz lazy_module_expr_located in
           Pack me )
       ; ( "Extension_node"
         , let+ e = lz lazy_extension_located in
           Extension_node_minor e )
       ; ( "Open"
         , enter
             (let+ l = loc
              and+ me = lz lazy_module_expr
              and+ ms = lz lazy_minors in
              Local_open (l, me, ms)) )
       ; ( "Bind"
         , enter
             (let+ l = loc
              and+ name = option_string
              and+ me = lz lazy_module_expr
              and+ ms = lz lazy_minors in
              Local_bind (l, { name; expr = me }, ms)) )
       ; ( "External"
         , let+ strs = enter (repeat string) in
           External strs )
       ])

and lazy_minors : minor list t Lazy.t = lazy (enter (repeat (lz lazy_minor)))

and lazy_access_entry : access_entry t Lazy.t =
  lazy
    (enter
       (let+ path = lz lazy_path_expr
        and+ l = loc
        and+ edge = edge in
        { path; loc = l; edge }))

and lazy_expression : expression t Lazy.t =
  lazy
    (sum
       [ ( "Open"
         , let+ me = lz lazy_module_expr in
           Open me )
       ; ( "Include_me"
         , let+ me = lz lazy_module_expr in
           Include me )
       ; ( "SigInclude"
         , let+ mt = lz lazy_module_type in
           SigInclude mt )
       ; ( "Bind"
         , enter
             (let+ name = option_string
              and+ expr = lz lazy_module_expr in
              Bind { name; expr }) )
       ; ( "Bind_sig"
         , enter
             (let+ name = option_string
              and+ expr = lz lazy_module_type in
              Bind_sig { name; expr }) )
       ; ( "Bind_rec"
         , let+ bindings =
             enter
               (repeat
                  (enter
                     (let+ name = option_string
                      and+ expr = lz lazy_module_expr in
                      { name; expr })))
           in
           Bind_rec bindings )
       ; ( "Minor"
         , let+ ms = lz lazy_minors in
           Minor ms )
       ; ( "Extension_node"
         , let+ e = lz lazy_extension in
           Extension_node e )
       ])

and lazy_extension : extension t Lazy.t =
  lazy
    (enter
       (let+ ext_name = string
        and+ ext_payload = lz lazy_extension_core in
        { ext_name; ext_payload }))

and lazy_extension_core : extension_core t Lazy.t =
  lazy
    (sum
       [ ( "Module"
         , let+ m = lz lazy_m2l in
           Ext_module m )
       ; ( "Val"
         , let+ ms = lz lazy_minors in
           Ext_val ms )
       ])

and lazy_extension_located : extension located t Lazy.t =
  lazy
    (enter
       (let+ data = lz lazy_extension
        and+ l = loc in
        { data; loc = l }))

and lazy_module_expr_located : module_expr located t Lazy.t =
  lazy
    (enter
       (let+ data = lz lazy_module_expr
        and+ l = loc in
        { data; loc = l }))

and lazy_simple_path_located : Path.simple located t Lazy.t =
  lazy
    (enter
       (let+ data = simple_path
        and+ l = loc in
        { data; loc = l }))

and lazy_located_expression : expression located t Lazy.t =
  lazy
    (enter
       (let+ data = lz lazy_expression
        and+ l = loc in
        { data; loc = l }))

and lazy_m2l : m2l t Lazy.t = lazy (enter (repeat (lz lazy_located_expression)))

(* {1 Top-level parsing} *)

let of_sexp (sexps : Dune_sexp.Ast.t list) =
  let top_parser =
    enter
      (let+ _version = enter (keyword "version" >>> triple int int int)
       and+ m2l = enter (keyword "m2l" >>> lz lazy_m2l) in
       m2l)
  in
  match sexps with
  | [ sexp ] -> Dune_sexp.Decoder.parse top_parser Stdune.Univ_map.empty sexp
  | _ -> failwith "unexpected codept output: expected single top-level sexp"
;;

(* {1 Compilation unit extraction} *)

module String_set = Set.Make (String)

let path_head = function
  | [] -> None
  | hd :: _ -> Some hd
;;

let rec expr_head : Path.expr -> string option = function
  | Path.Simple p -> path_head p
  | Path.Apply { f; _ } -> expr_head f
;;

let add_simple_path acc p =
  match path_head p with
  | Some name -> String_set.add name acc
  | None -> acc
;;

let add_expr_path acc p =
  match expr_head p with
  | Some name -> String_set.add name acc
  | None -> acc
;;

let rec collect_module_expr acc = function
  | Ident p -> add_simple_path acc p
  | Apply { f; x } -> collect_module_expr (collect_module_expr acc f) x
  | Fun { arg; body } -> collect_module_expr (collect_functor_arg acc arg) body
  | Constraint (me, mt) -> collect_module_type (collect_module_expr acc me) mt
  | Str m2l -> collect_m2l acc m2l
  | Val minors -> collect_minors acc minors
  | Extension_node_me ext -> collect_extension acc ext
  | Abstract | Unpacked -> acc
  | Open_me { opens; expr } ->
    let acc =
      List.fold_left (fun acc { data; _ } -> add_simple_path acc data) acc opens
    in
    collect_module_expr acc expr
  | Proj { me; proj } -> add_simple_path (collect_module_expr acc me) proj

and collect_module_type acc = function
  | Alias p -> add_simple_path acc p
  | Ident_mt p -> add_expr_path acc p
  | Sig m2l -> collect_m2l acc m2l
  | Fun_mt { arg; body } -> collect_module_type (collect_functor_arg acc arg) body
  | Of me -> collect_module_expr acc me
  | Extension_node_mt ext -> collect_extension acc ext
  | Abstract_mt -> acc
  | With { body; constraints } ->
    List.fold_left collect_with_constraint (collect_module_type acc body) constraints

and collect_with_constraint acc { lhs; rhs; _ } =
  let acc = add_simple_path acc lhs in
  match rhs with
  | Type minors -> collect_minors acc minors
  | Module { data; _ } -> add_simple_path acc data
  | Module_type mt -> collect_module_type acc mt

and collect_functor_arg acc = function
  | None -> acc
  | Some { arg_signature; _ } -> collect_module_type acc arg_signature

and collect_minor acc = function
  | Access entries ->
    List.fold_left (fun acc { path; _ } -> add_expr_path acc path) acc entries
  | Pack { data; _ } -> collect_module_expr acc data
  | Extension_node_minor { data; _ } -> collect_extension acc data
  | Local_open (_, me, minors) -> collect_minors (collect_module_expr acc me) minors
  | Local_bind (_, { expr; _ }, minors) ->
    collect_minors (collect_module_expr acc expr) minors
  | External _ -> acc

and collect_minors acc minors = List.fold_left collect_minor acc minors

and collect_expression acc = function
  | Open me | Include me -> collect_module_expr acc me
  | SigInclude mt -> collect_module_type acc mt
  | Bind { expr; _ } -> collect_module_expr acc expr
  | Bind_sig { expr; _ } -> collect_module_type acc expr
  | Bind_rec bindings ->
    List.fold_left (fun acc { expr; _ } -> collect_module_expr acc expr) acc bindings
  | Minor minors -> collect_minors acc minors
  | Extension_node ext -> collect_extension acc ext

and collect_extension acc { ext_payload; _ } =
  match ext_payload with
  | Ext_module m2l -> collect_m2l acc m2l
  | Ext_val minors -> collect_minors acc minors

and collect_m2l acc m2l =
  List.fold_left (fun acc { data; _ } -> collect_expression acc data) acc m2l
;;

let compilation_units m2l = collect_m2l String_set.empty m2l |> String_set.elements
