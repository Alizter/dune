(** Parse codept's M2L sexp output and extract referenced compilation units.

    codept's [-m2l] mode outputs a structured S-expression representing the
    module-level AST of a single OCaml file. This module defines the M2L data
    structure, parses the sexp output, and extracts compilation unit references. *)

(** {1 Path types} *)

module Path : sig
  (** A simple module path like [A.B.C] is represented as [\["A"; "B"; "C"\]]. *)
  type simple = string list

  (** An expression-level module path, which can include functor applications. *)
  type expr =
    | Simple of simple
    | Apply of
        { f : expr
        ; x : expr
        ; proj : simple option
        }
end

(** {1 Location} *)

module Loc : sig
  type t =
    | Simple of int * int * int
    | Multiline of
        { start : int * int
        ; stop : int * int
        }
end

(** {1 Edge types} *)

module Edge : sig
  type t =
    | Normal
    | Epsilon
end

(** {1 M2L AST} *)

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

(** {1 Sexp parsing} *)

(** [of_sexp s] parses the M2L sexp output from codept (the output of
    [codept -m2l file.ml]) and returns the M2L AST. *)
val of_sexp : Dune_sexp.Ast.t list -> m2l

(** {1 Compilation unit extraction} *)

(** [compilation_units m2l] walks the M2L AST and returns the set of
    top-level module names (compilation units) referenced by the file.
    Each module path's first component is the compilation unit. *)
val compilation_units : m2l -> string list
