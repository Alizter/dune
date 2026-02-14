Debug test showing refinement events with trace_file_opens.

  $ cat > dune-project << EOF
  > (lang dune 3.0)
  > EOF

  $ cat > dune << EOF
  > (executable (name test))
  > EOF

  $ cat > test.ml << EOF
  > let () = print_endline "hello"
  > EOF

Build with trace_file_opens enabled:

  $ DUNE_CONFIG__TRACE_FILE_OPENS=enabled dune build

Show all refinement events:

  $ dune trace cat 2>/dev/null | jq 'select(.name == "refined") | {head: .args.head, actual: .args.actual_deps, refined: .args.refined_deps}'
  {
    "head": "_build/default/.dune/configurator",
    "actual": [],
    "refined": []
  }
  {
    "head": "_build/default/.dune/configurator.v2",
    "actual": [],
    "refined": []
  }
  {
    "head": "_build/default/.merlin-conf/exe-test",
    "actual": [],
    "refined": []
  }
  {
    "head": "_build/default/test.mli",
    "actual": [],
    "refined": []
  }
  {
    "head": "_build/default/.test.eobjs/byte/dune__exe__Test.cmi",
    "actual": [
      "/nix/store/0gxysxzzvzqm2m2aznix02pm05bmqm1q-ocaml+fp-5.4.0/bin/ocamlc.opt",
      "_build/default/test.mli"
    ],
    "refined": [
      "/nix/store/0gxysxzzvzqm2m2aznix02pm05bmqm1q-ocaml+fp-5.4.0/bin/ocamlc.opt",
      "_build/default/test.mli"
    ]
  }
  {
    "head": "_build/default/test.ml",
    "actual": [
      "test.ml"
    ],
    "refined": []
  }
  {
    "head": "_build/default/.test.eobjs/native/dune__exe__Test.cmx",
    "actual": [
      "/nix/store/0gxysxzzvzqm2m2aznix02pm05bmqm1q-ocaml+fp-5.4.0/bin/ocamlopt.opt",
      "_build/default/.test.eobjs/byte/dune__exe__Test.cmi",
      "_build/default/test.ml"
    ],
    "refined": [
      "/nix/store/0gxysxzzvzqm2m2aznix02pm05bmqm1q-ocaml+fp-5.4.0/bin/ocamlopt.opt",
      "_build/default/.test.eobjs/byte/dune__exe__Test.cmi",
      "_build/default/test.ml"
    ]
  }
  {
    "head": "_build/default/test.exe",
    "actual": [
      "/nix/store/0gxysxzzvzqm2m2aznix02pm05bmqm1q-ocaml+fp-5.4.0/bin/ocamlopt.opt",
      "_build/default/.test.eobjs/native/dune__exe__Test.cmx",
      "_build/default/.test.eobjs/native/dune__exe__Test.o"
    ],
    "refined": [
      "/nix/store/0gxysxzzvzqm2m2aznix02pm05bmqm1q-ocaml+fp-5.4.0/bin/ocamlopt.opt",
      "_build/default/.test.eobjs/native/dune__exe__Test.cmx",
      "_build/default/.test.eobjs/native/dune__exe__Test.o"
    ]
  }
