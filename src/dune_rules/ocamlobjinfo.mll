{
open Import

type t = Module_name.Unique.Set.t Ml_kind.Dict.t

let to_dyn = Ml_kind.Dict.to_dyn Module_name.Unique.Set.to_dyn

let empty =
  { Ml_kind.Dict.
    intf = Module_name.Unique.Set.empty
  ; impl = Module_name.Unique.Set.empty
  }

let add_intf (t : t) i =
  { t with intf = Module_name.Unique.Set.add t.intf (Module_name.Unique.of_string i) }
let add_impl (t : t) i =
  { t with impl = Module_name.Unique.Set.add t.impl (Module_name.Unique.of_string i) }

(* Version that also captures interface digests from ocamlobjinfo output.
   The digest is OCaml's CRC computed over the module's .cmi interface. *)
type with_interface_digests = (Module_name.Unique.t * string) list Ml_kind.Dict.t

let empty_with_interface_digests =
  { Ml_kind.Dict.
    intf = []
  ; impl = []
  }

let add_intf_with_interface_digest (t : with_interface_digests) ~name ~digest =
  { t with intf = (Module_name.Unique.of_string name, digest) :: t.intf }
let add_impl_with_interface_digest (t : with_interface_digests) ~name ~digest =
  { t with impl = (Module_name.Unique.of_string name, digest) :: t.impl }
}

let newline = '\r'? '\n'
let ws = [' ' '\t']+
let hash = ['0'-'9' 'a'-'z' '-']+
let name = ['A'-'Z'] ['A'-'Z' 'a'-'z' '0'-'9' '_']*

rule ocamlobjinfo acc_units acc = parse
  | "Interfaces imported:" newline { intfs acc_units acc lexbuf }
  | "Implementations imported:" newline { impls acc_units acc lexbuf }
  | _ { ocamlobjinfo acc_units acc lexbuf }
  | eof { acc :: acc_units }
and intfs acc_units acc = parse
  | ws hash ws (name as name) newline { intfs acc_units (add_intf acc name) lexbuf }
  | "Implementations imported:" newline { impls acc_units acc lexbuf }
  | "File " [^ '\n']+ newline { ocamlobjinfo (acc :: acc_units) empty lexbuf }
  | [^ '\n' ]* newline { intfs acc_units acc lexbuf }
  | _ | eof { acc :: acc_units }
and impls acc_units acc = parse
  | ws hash ws (name as name) newline { impls acc_units (add_impl acc name) lexbuf }
  | "File " [^ '\n']+ newline { ocamlobjinfo (acc :: acc_units) empty lexbuf }
  | [^ '\n' ]* newline {  impls acc_units acc lexbuf }
  | _ | eof { acc :: acc_units }

and archive acc = parse
  | "Unit name:" ws (name as name) { archive (Module_name.Unique.Set.add acc (Module_name.Unique.of_string name)) lexbuf }
  | _ { archive acc lexbuf }
  | eof { acc }

(* Parser rules that capture interface digests *)
and ocamlobjinfo_with_interface_digests acc_units acc = parse
  | "Interfaces imported:" newline { intfs_with_interface_digests acc_units acc lexbuf }
  | "Implementations imported:" newline { impls_with_interface_digests acc_units acc lexbuf }
  | _ { ocamlobjinfo_with_interface_digests acc_units acc lexbuf }
  | eof { acc :: acc_units }
and intfs_with_interface_digests acc_units acc = parse
  | ws (hash as digest) ws (name as name) newline { intfs_with_interface_digests acc_units (add_intf_with_interface_digest acc ~name ~digest) lexbuf }
  | "Implementations imported:" newline { impls_with_interface_digests acc_units acc lexbuf }
  | "File " [^ '\n']+ newline { ocamlobjinfo_with_interface_digests (acc :: acc_units) empty_with_interface_digests lexbuf }
  | [^ '\n' ]* newline { intfs_with_interface_digests acc_units acc lexbuf }
  | _ | eof { acc :: acc_units }
and impls_with_interface_digests acc_units acc = parse
  | ws (hash as digest) ws (name as name) newline { impls_with_interface_digests acc_units (add_impl_with_interface_digest acc ~name ~digest) lexbuf }
  | "File " [^ '\n']+ newline { ocamlobjinfo_with_interface_digests (acc :: acc_units) empty_with_interface_digests lexbuf }
  | [^ '\n' ]* newline { impls_with_interface_digests acc_units acc lexbuf }
  | _ | eof { acc :: acc_units }

{
let parse s = Lexing.from_string s |> ocamlobjinfo [] empty  |> List.rev

let parse_with_interface_digests s =
  Lexing.from_string s |> ocamlobjinfo_with_interface_digests [] empty_with_interface_digests |> List.rev

let parse_archive s =
  Lexing.from_string s
  |> archive Module_name.Unique.Set.empty

let rules (ocaml : Ocaml_toolchain.t) ~dir ~sandbox ~units =
  let no_approx =
    if Ocaml.Version.ooi_supports_no_approx ocaml.version then
      [Command.Args.A "-no-approx"]
    else
      []
  in
  let no_code =
    if Ocaml.Version.ooi_supports_no_code ocaml.version then
      [Command.Args.A "-no-code"]
    else
      []
  in
  let observing_facts =
    List.map units ~f:(fun unit ->
      Dep.Facts.singleton (Dep.file unit) (Dep.Fact.nothing))
    |> Dep.Facts.union_all
  in
  let open Action_builder.O in
  let* action =
    Command.run' ?sandbox
      ~dir:(Path.build dir) ocaml.ocamlobjinfo
      (List.concat
         [ no_approx
         ; no_code
         ; [ Deps units ]
         ])
  in
  (Dune_engine.Build_system.execute_action_stdout
    ~observing_facts
    { Rule.Anonymous_action.action
    ; loc = Loc.none
    ; dir
    ; alias = None
    }
  |> Action_builder.of_memo)
  >>| parse

let rules_with_interface_digests (ocaml : Ocaml_toolchain.t) ~dir ~sandbox ~units =
  let no_approx =
    if Ocaml.Version.ooi_supports_no_approx ocaml.version then
      [Command.Args.A "-no-approx"]
    else
      []
  in
  let no_code =
    if Ocaml.Version.ooi_supports_no_code ocaml.version then
      [Command.Args.A "-no-code"]
    else
      []
  in
  let observing_facts =
    List.map units ~f:(fun unit ->
      Dep.Facts.singleton (Dep.file unit) (Dep.Fact.nothing))
    |> Dep.Facts.union_all
  in
  let open Action_builder.O in
  let* action =
    Command.run' ?sandbox
      ~dir:(Path.build dir) ocaml.ocamlobjinfo
      (List.concat
         [ no_approx
         ; no_code
         ; [ Deps units ]
         ])
  in
  (Dune_engine.Build_system.execute_action_stdout
    ~observing_facts
    { Rule.Anonymous_action.action
    ; loc = Loc.none
    ; dir
    ; alias = None
    }
  |> Action_builder.of_memo)
  >>| parse_with_interface_digests

let archive_rules (ocaml : Ocaml_toolchain.t) ~dir ~sandbox ~archive =
  let observing_facts =
    Dep.Facts.singleton (Dep.file archive) (Dep.Fact.nothing)
  in
  let open Action_builder.O in
  let* action =
    Command.run' ?sandbox
      ~dir:(Path.build dir) ocaml.ocamlobjinfo
      [ Dep archive ]
  in
  (Dune_engine.Build_system.execute_action_stdout
    ~observing_facts
    { Rule.Anonymous_action.action
    ; loc = Loc.none
    ; dir
    ; alias = None
    }
  |> Action_builder.of_memo)
  >>| parse_archive
}
