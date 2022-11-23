open Stdune
open Dune_nix.Ast

let show x = Pp.to_fmt Format.std_formatter x

let example =
  attr
    [ ("foo", string "bar")
    ; ("baz", int 42)
    ; ("att", attr [ ("a", string "b"); ("c", float 3.14) ])
    ; ("goo", list [ string "foo"; int 42; path "bar/zoo/gar" ])
    ; ("zoo", list [ string "hello"; int 10; float 10.5 ])
    ; ("cond", if_then_else (bool true) (string "foo") (string "bar"))
    ; ( "cond2"
      , if_then_else (bool false)
          (list
             [ string "hello_something_really_very_long_please"
             ; int 10
             ; float 10.5
             ])
          (string "bar") )
    ; ( "zoo"
      , list
          [ string "hello_something_really_very_long_please"
          ; int 10
          ; float 10.5
          ] )
    ; ( "aaa"
      , let_
          [ ("a", string "b")
          ; ( "c"
            , list
                [ string
                    "hello_something_really_very_long_please_asdfasdfasdfasdf"
                ; int 10
                ; float 10.5
                ] )
          ]
          (attr
             [ ("foo", string "bar")
             ; ("baz", int 42)
             ; ("goo", list [ string "foo"; int 42; path "bar" ])
             ; ("zoo", list [ string "hello"; int 10; float 10.5 ])
             ; ( "zoo"
               , list
                   [ string
                       "hello_something_really_very_long_please_and_even_longer_if_you_allow_it"
                   ; int 10
                   ; float 10.5
                   ] )
             ]) )
    ]

let%expect_test _ =
  show (pp example);
  [%expect
    {|
    {
      foo = "bar";
      baz = 42;
      att = { a = "b"; c = 3.14; };
      goo = [ "foo" 42 bar/zoo/gar ];
      zoo = [ "hello" 10 10.5 ];
      cond = if true then
                       "foo"
                       else
                         "bar";
      cond2 = if false then
                         [ "hello_something_really_very_long_please" 10 10.5
                         ]
                         else
                           "bar";
      zoo = [ "hello_something_really_very_long_please" 10 10.5 ];
      aaa = let
              a = "b";
              c = [
                    "hello_something_really_very_long_please_asdfasdfasdfasdf"
                    10
                    10.5
              ];
      in
      {
        foo = "bar";
        baz = 42;
        goo = [ "foo" 42 bar ];
        zoo = [ "hello" 10 10.5 ];
        zoo = [
                "hello_something_really_very_long_please_and_even_longer_if_you_allow_it"
                10
                10.5
        ];
      };
    }
    |}]

let current_dune_flake =
  attr
    [ ( "inputs"
      , attr
          [ ("nixpkgs.url", string "github:nixos/nixpkgs/nixpkgs-unstable")
          ; ("nix-overlays.url", string "github:anmonteiro/nix-overlays")
          ; ("flake-utils.url", string "github:numtide/flake-utils")
          ; ( "ocamllsp.url"
            , string "git+https://www.github.com/ocaml/ocaml-lsp?submodules=1"
            )
          ; ( "opam-nix"
            , attr
                [ ("url", string "github:avsm/opam-nix")
                ; ("inputs.opam-repository.follows", string "opam-repository")
                ] )
          ; ( "opam-repository"
            , attr
                [ ("url", string "github:ocaml/opam-repository")
                ; ("flake", bool false)
                ] )
          ; ("merlange.url", string "github:melange-re/melange")
          ] )
    ; ( "outputs"
      , fun_set ~at:"inputs"
          [ `A "self"
          ; `A "flake-utls"
          ; `A "opam-nix"
          ; `A "nixpkgs"
          ; `A "ocamllsp"
          ; `A "opam-repository"
          ; `A "melange"
          ; `A "nix-overlays"
          ]
          (let_
             [ ("package", string "dune") ]
             (fun_app
                (string "flake-utils.lib.eachDefaultSystem")
                (fun_ "system"
                   (let_
                      [ ( "devPackages"
                        , attr
                            [ ("menhir", string "*")
                            ; ("lwt", string "*")
                            ; ("csexp", string "*")
                            ; ("core_bench", string "*")
                            ; ("js_of_ocaml", string "*")
                            ; ("js_of_ocaml-compiler", string "*")
                            ; ("mdx", string "*")
                            ; ("odoc", string "*")
                            ; ("ppx_expect", string "*")
                            ; ("ppxlib", string "*")
                            ; ("ctypes", string "*")
                            ; ("utop", string "*")
                            ; ("cinaps", string "*")
                            ; ("ocamlfind", string "1.9.2")
                            ] )
                      ]
                      (int 0))))) )
    ]

let%expect_test _ =
  show (pp current_dune_flake);
  [%expect
    {|
    {
      inputs = {
                 nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
                 nix-overlays.url = "github:anmonteiro/nix-overlays";
                 flake-utils.url = "github:numtide/flake-utils";
                 ocamllsp.url = "git+https://www.github.com/ocaml/ocaml-lsp?submodules=1";
                 opam-nix = {
                              url = "github:avsm/opam-nix";
                              inputs.opam-repository.follows = "opam-repository";
                 };
                 opam-repository = {
                                     url = "github:ocaml/opam-repository";
                                     flake = false;
                 };
                 merlange.url = "github:melange-re/melange";
      };
      outputs = {
                  self,
                  flake-utls,
                  opam-nix,
                  nixpkgs,
                  ocamllsp,
                  opam-repository,
                  melange,
                  nix-overlays
                }@inputs: let package = "dune"; in
                "flake-utils.lib.eachDefaultSystem"
                (
                  system:
                  let
                    devPackages = {
                                    menhir = "*";
                                    lwt = "*";
                                    csexp = "*";
                                    core_bench = "*";
                                    js_of_ocaml = "*";
                                    js_of_ocaml-compiler = "*";
                                    mdx = "*";
                                    odoc = "*";
                                    ppx_expect = "*";
                                    ppxlib = "*";
                                    ctypes = "*";
                                    utop = "*";
                                    cinaps = "*";
                                    ocamlfind = "1.9.2";
                    };
                  in 0
                );
    }
    |}]
