open Import

let nix_var_of_path (p : Path.t) =
  (* add "nix sepeartors" *)
  (match p with
  | In_build_dir dir -> Path.Build.explode dir
  | _ -> assert false)
  |> String.concat ~sep:"_ns_"

let translate ~expanded_deps ~file_targets ~dir_targets
    (action : Dune_engine.Action.t) =
  let build_inputs =
    Ast.list
    @@ Path.Set.to_list_map expanded_deps ~f:(fun x ->
           nix_var_of_path x |> Ast.string)
  in
  let targets = Path.Build.Set.to_list file_targets in
  let outputs =
    Ast.list
    @@ Path.Build.Set.to_list_map
         ~f:(fun x -> Path.build x |> nix_var_of_path |> Ast.string)
         file_targets
  in
  (* We need to make our output directory *)
  let setup =
    (* TODO envs goes here I think *)
    [ "$coreutils/bin/mkdir -p $out"; "" ]
  in
  let install =
    List.map targets ~f:(fun x ->
        Path.Build.set_build_dir
          (Path.Outside_build_dir.External
             (Path.External.Expert.of_string (nix_var_of_path (Path.build x))));
        Path.Build.to_string x)
  in
  let build_command =
    action |> Dune_engine.Action.for_shell |> Dune_engine.Action_to_sh.pp
    |> Format.asprintf "%a" Pp.to_fmt
    |> fun x -> String.concat ~sep:"\n" (setup @ [ x ] @ install) |> Ast.string
  in
  (* TODO we know which files we need but which rules did they come from? *)
  ignore dir_targets;

  Ast.(
    with_ (fun_app (fun_app (builtin "import") (path "<nixpkgs>")) (attr []))
    @@ fun_app (builtin "derivation")
         (attr ~inherit_:[ "coreutils" ]
            [ ("name", string "foo")
            ; ("system", builtin "builtins.currentSystem")
            ; ("buildInputs", build_inputs)
            ; ("builder", string "${bash}/bin/bash")
            ; ("args", list [ string "-c"; build_command ])
            ; ("outputs", outputs)
            ]))
