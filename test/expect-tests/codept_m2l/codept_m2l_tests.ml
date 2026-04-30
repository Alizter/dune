open Stdune

let parse_and_extract s =
  let sexps = Dune_sexp.Parser.parse_string ~fname:"test" ~mode:Many s in
  let m2l = Codept_m2l.of_sexp sexps in
  let units = Codept_m2l.compilation_units m2l in
  List.iter units ~f:(fun u -> print_endline u)
;;

let () = Dune_tests_common.init ()

let run_codept ?(intf = false) source =
  let ext = if intf then ".mli" else ".ml" in
  let flag = if intf then "-intf" else "-impl" in
  let tmp = Stdlib.Filename.temp_file "codept_test" ext in
  Io.write_file (Path.of_string tmp) source;
  let cmd = Printf.sprintf "codept -m2l %s %s" flag tmp in
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 256 in
  (try
     while true do
       Buffer.add_char buf (input_char ic)
     done
   with
   | End_of_file -> ());
  let _status = Unix.close_process_in ic in
  Stdlib.Sys.remove tmp;
  parse_and_extract (Buffer.contents buf)
;;

(* {1 Sexp unit tests — raw fixtures from codept output} *)

let%expect_test "sexp: simple open and access" =
  parse_and_extract
    {|((version(0 11 0))(m2l(((Open(Ident(Foo)))(Simple(1 0 8)))((Minor((Access(((S(Bar))(Simple(2 8 17))Normal)))))(Simple(2 0 17))))))|};
  [%expect
    {|
    Bar
    Foo |}]
;;

let%expect_test "sexp: module alias in mli" =
  parse_and_extract
    {|((version(0 11 0))(m2l(((Bind((Some Re)(Constraint(Abstract(Alias(Original_name))))))(Simple(1 0 25))))))|};
  [%expect {| Original_name |}]
;;

let%expect_test "sexp: include" =
  parse_and_extract
    {|((version(0 11 0))(m2l(((Include_me(Ident(Baz)))(Simple(1 0 11))))))|};
  [%expect {| Baz |}]
;;

let%expect_test "sexp: functor application" =
  parse_and_extract
    {|((version(0 11 0))(m2l(((Bind((Some M)(Apply((Ident(Foo Make))(Ident(Bar))))))(Simple(1 0 24))))))|};
  [%expect
    {|
    Bar
    Foo |}]
;;

let%expect_test "sexp: module type constraint" =
  parse_and_extract
    {|((version(0 11 0))(m2l(((Bind((Some M)(Constraint(Abstract(Ident(S(Foo S)))))))(Simple(1 0 16))))))|};
  [%expect {| Foo |}]
;;

let%expect_test "sexp: complex" =
  parse_and_extract
    {|((version(0 11 0))(m2l(((Open(Ident(Stdlib)))(Simple(1 0 11)))((Bind((Some M)(Ident(Foo Bar))))(Simple(2 0 18)))((Include_me(Ident(Baz)))(Simple(3 0 11)))((Minor((Access(((S(Wibble))(Simple(5 9 17))Epsilon)((S(Qux Something))(Simple(4 8 27))Normal)))))(Simple(5 0 17))))))|};
  [%expect
    {|
    Baz
    Foo
    Qux
    Stdlib
    Wibble |}]
;;

let%expect_test "sexp: module type of" =
  parse_and_extract
    {|((version(0 11 0))(m2l(((Bind_sig((Some S)(Of(Ident(Foo)))))(Simple(1 0 34))))))|};
  [%expect {| Foo |}]
;;

let%expect_test "sexp: extension node" =
  parse_and_extract
    {|((version(0 11 0))(m2l(((Minor((Extension_node((test(Module()))(Simple(1 8 18))))))(Simple(1 0 18))))))|};
  [%expect {||}]
;;

let%expect_test "sexp: local open" =
  parse_and_extract
    {|((version(0 11 0))(m2l(((Minor((Open((Simple(1 8 11))(Ident(Foo))()))))(Simple(1 0 23))))))|};
  [%expect {| Foo |}]
;;

let%expect_test "sexp: external" =
  parse_and_extract
    {|((version(0 11 0))(m2l(((Minor((External(caml_f))))(Simple(1 0 34))))))|};
  [%expect {||}]
;;

let%expect_test "sexp: multiline loc" =
  parse_and_extract
    {|((version(0 11 0))(m2l(((Minor((Access(((S(Uses_lib))(Simple(2 13 31))Normal)((S(No_use_lib))(Simple(3 13 31))Normal)))))(Multiline((1 0)(3 34)))))))|};
  [%expect
    {|
    No_use_lib
    Uses_lib |}]
;;

let%expect_test "sexp: empty m2l" =
  parse_and_extract {|((version(0 11 0))(m2l()))|};
  [%expect {||}]
;;

let%expect_test "sexp: bind_rec" =
  parse_and_extract
    {|((version(0 11 0))(m2l(((Bind_rec(((Some A)(Ident(Foo)))((Some B)(Ident(Bar)))))(Simple(1 0 40))))))|};
  [%expect
    {|
    Bar
    Foo |}]
;;

let%expect_test "sexp: sig include" =
  parse_and_extract
    {|((version(0 11 0))(m2l(((SigInclude(Alias(Foo)))(Simple(1 0 15))))))|};
  [%expect {| Foo |}]
;;

let%expect_test "sexp: epsilon edge" =
  parse_and_extract
    {|((version(0 11 0))(m2l(((Minor((Access(((S(Foo))(Simple(1 9 12))Epsilon)))))(Simple(1 0 12))))))|};
  [%expect {| Foo |}]
;;

(* {1 Integration tests: run codept on real OCaml source via temp files} *)

let%expect_test "codept: simple access" =
  run_codept "let x = Foo.bar\nlet y = Baz.qux";
  [%expect
    {|
    Baz
    Foo |}]
;;

let%expect_test "codept: open and access" =
  run_codept "open Foo\nlet x = Bar.value";
  [%expect
    {|
    Bar
    Foo |}]
;;

let%expect_test "codept: module alias mli" =
  run_codept ~intf:true "module Re = Original_name";
  [%expect {| Original_name |}]
;;

let%expect_test "codept: module type constraint mli" =
  run_codept ~intf:true "module M : Foo.S";
  [%expect {| Foo |}]
;;

let%expect_test "codept: include" =
  run_codept "include Baz";
  [%expect {| Baz |}]
;;

let%expect_test "codept: functor" =
  run_codept "module M = Foo.Make(Bar)";
  [%expect
    {|
    Bar
    Foo |}]
;;

let%expect_test "codept: multiline body" =
  run_codept
    "let () =\n  print_int (Uses_lib.get_value ());\n  print_int (No_use_lib.compute 5)";
  [%expect
    {|
    No_use_lib
    Uses_lib |}]
;;

let%expect_test "codept: no deps" =
  run_codept "let x = 42";
  [%expect {||}]
;;

let%expect_test "codept: external" =
  run_codept {|external f : int -> int = "caml_f"|};
  [%expect {||}]
;;

let%expect_test "codept: local open" =
  run_codept "let x = Foo.(bar + baz)";
  [%expect {| Foo |}]
;;

let%expect_test "codept: module type of" =
  run_codept ~intf:true "module type S = module type of Foo";
  [%expect {| Foo |}]
;;

let%expect_test "codept: complex" =
  run_codept
    "open Stdlib\n\
     module M = Foo.Bar\n\
     include Baz\n\
     let x = Qux.Something.value\n\
     type t = Wibble.t";
  [%expect
    {|
    Baz
    Foo
    Qux
    Stdlib
    Wibble |}]
;;
