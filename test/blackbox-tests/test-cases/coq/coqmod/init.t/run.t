Testing compilation of the Coq prelude using coqmod

  $ dune build Init/
  adding [ "Byte"; "Init" ] to require map
  adding [ "Notations"; "Init" ] to require map
  adding [ "Prelude"; "Init" ] to require map
  adding [ "Wf"; "Init" ] to require map
  adding [ "Byte"; "Init" ] to require map
  adding [ "Notations"; "Init" ] to require map
  adding [ "Prelude"; "Init" ] to require map
  adding [ "Wf"; "Init" ] to require map
  adding [ "Byte"; "Init" ] to require map
  adding [ "Notations"; "Init" ] to require map
  adding [ "Prelude"; "Init" ] to require map
  adding [ "Wf"; "Init" ] to require map
  adding [ "Byte"; "Init" ] to require map
  adding [ "Notations"; "Init" ] to require map
  adding [ "Prelude"; "Init" ] to require map
  adding [ "Wf"; "Init" ] to require map
  prefix: None	 suffix: [ "Coq"; "Init"; "Byte" ]	 requires: []
    Coq_require_map.find_all ~prefix:[] ~suffix:[ "Coq"; "Init"; "Byte" ]
    - prefix:[] suffix:[ "Coq"; "Init"; "Byte" ]
    loop acc:[] t:some map path[ "Byte"; "Init"; "Coq" ]
    - find p:"Byte"
      - Some Tree
    loop acc:[] t:some map path[ "Init"; "Coq" ]
    - find p:"Init"
      - Some Leaf s:{ source =
      { source = "default/Init/Byte.v"; prefix = [ "Init" ]; name = "Byte" }
  ; theory_prefix = [ "Coq" ]
  ; obj_dir = "default"
  }
  prefix: None	 suffix: [ "Coq"; "Init"; "Wf" ]	 requires: []
    Coq_require_map.find_all ~prefix:[] ~suffix:[ "Coq"; "Init"; "Wf" ]
    - prefix:[] suffix:[ "Coq"; "Init"; "Wf" ]
    loop acc:[] t:some map path[ "Wf"; "Init"; "Coq" ]
    - find p:"Wf"
      - Some Tree
    loop acc:[] t:some map path[ "Init"; "Coq" ]
    - find p:"Init"
      - Some Leaf s:{ source = { source = "default/Init/Wf.v"; prefix = [ "Init" ]; name = "Wf" }
  ; theory_prefix = [ "Coq" ]
  ; obj_dir = "default"
  }
  prefix: None	 suffix: [ "Notations" ]	 requires: []
    Coq_require_map.find_all ~prefix:[] ~suffix:[ "Notations" ]
    - prefix:[] suffix:[ "Notations" ]
    loop acc:[] t:some map path[ "Notations" ]
    - find p:"Notations"
      - Some Tree
    loop acc:[] t:some map path[]
    - fold
    check_prefix { source =
      { source = "default/Init/Notations.v"
      ; prefix = [ "Init" ]
      ; name = "Notations"
      }
  ; theory_prefix = [ "Coq" ]
  ; obj_dir = "default"
  } [ "Coq"; "Init"; "Notations" ] []
    check_prefix = true
  File "_build/default/Init/Prelude.v", line 3, characters 8-21:
  3 | Require Coq.Init.Byte.
              ^^^^^^^^^^^^^
  Error: could not find module "Coq.Init.Byte".
  map
    { "Byte" :
        Tree
          map
            { "Init" :
                Leaf
                  { source =
                      { source = "default/Init/Byte.v"
                      ; prefix = [ "Init" ]
                      ; name = "Byte"
                      }
                  ; theory_prefix = [ "Coq" ]
                  ; obj_dir = "default"
                  }
            }
    ; "Notations" :
        Tree
          map
            { "Init" :
                Leaf
                  { source =
                      { source = "default/Init/Notations.v"
                      ; prefix = [ "Init" ]
                      ; name = "Notations"
                      }
                  ; theory_prefix = [ "Coq" ]
                  ; obj_dir = "default"
                  }
            }
    ; "Prelude" :
        Tree
          map
            { "Init" :
                Leaf
                  { source =
                      { source = "default/Init/Prelude.v"
                      ; prefix = [ "Init" ]
                      ; name = "Prelude"
                      }
                  ; theory_prefix = [ "Coq" ]
                  ; obj_dir = "default"
                  }
            }
    ; "Wf" :
        Tree
          map
            { "Init" :
                Leaf
                  { source =
                      { source = "default/Init/Wf.v"
                      ; prefix = [ "Init" ]
                      ; name = "Wf"
                      }
                  ; theory_prefix = [ "Coq" ]
                  ; obj_dir = "default"
                  }
            }
    }
  
  File "_build/default/Init/Prelude.v", line 4, characters 15-26:
  4 | Require Export Coq.Init.Wf.
                     ^^^^^^^^^^^
  Error: could not find module "Coq.Init.Wf".
  map
    { "Byte" :
        Tree
          map
            { "Init" :
                Leaf
                  { source =
                      { source = "default/Init/Byte.v"
                      ; prefix = [ "Init" ]
                      ; name = "Byte"
                      }
                  ; theory_prefix = [ "Coq" ]
                  ; obj_dir = "default"
                  }
            }
    ; "Notations" :
        Tree
          map
            { "Init" :
                Leaf
                  { source =
                      { source = "default/Init/Notations.v"
                      ; prefix = [ "Init" ]
                      ; name = "Notations"
                      }
                  ; theory_prefix = [ "Coq" ]
                  ; obj_dir = "default"
                  }
            }
    ; "Prelude" :
        Tree
          map
            { "Init" :
                Leaf
                  { source =
                      { source = "default/Init/Prelude.v"
                      ; prefix = [ "Init" ]
                      ; name = "Prelude"
                      }
                  ; theory_prefix = [ "Coq" ]
                  ; obj_dir = "default"
                  }
            }
    ; "Wf" :
        Tree
          map
            { "Init" :
                Leaf
                  { source =
                      { source = "default/Init/Wf.v"
                      ; prefix = [ "Init" ]
                      ; name = "Wf"
                      }
                  ; theory_prefix = [ "Coq" ]
                  ; obj_dir = "default"
                  }
            }
    }
  
  [1]

  $ ls Init
  Byte.v
  Notations.v
  Prelude.v
  Wf.v
  _CoqProject
