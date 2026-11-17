open Stdune
open Dune_engine
module Gen_rules = Build_config.Gen_rules

let () = Dune_tests_common.init ()

let run rules =
  Fiber.run (Memo.run rules) ~iter:(fun () ->
    Code_error.raise "Unexpected suspension in generated rules test" [])
;;

let%expect_test "empty generated rule combinations remain deferred" =
  let calls = ref 0 in
  let effectful =
    Gen_rules.make
      (Memo.of_thunk (fun () ->
         incr calls;
         Memo.return Rules.empty))
  in
  List.iter
    [ "both empty", Gen_rules.no_rules, Gen_rules.no_rules
    ; "empty left", Gen_rules.no_rules, effectful
    ; "empty right", effectful, Gen_rules.no_rules
    ; "same effectful record", effectful, effectful
    ]
    ~f:(fun (name, left, right) ->
      calls := 0;
      let rules =
        match Gen_rules.combine left right with
        | Rules { rules; _ } -> rules
        | Unknown_context | Redirect_to_parent _ ->
          Code_error.raise "Expected a normal generated-rules result" []
      in
      let deferred = !calls = 0 in
      let result = run rules in
      printfn
        "%s: deferred=%b calls=%d empty=%b"
        name
        deferred
        !calls
        (Path.Build.Map.is_empty (Rules.to_map result)));
  [%expect
    {|
    both empty: deferred=true calls=0 empty=true
    empty left: deferred=true calls=1 empty=true
    empty right: deferred=true calls=1 empty=true
    same effectful record: deferred=true calls=2 empty=true
    |}]
;;

let combine left right =
  match Gen_rules.combine left right with
  | Rules rules -> rules
  | Unknown_context | Redirect_to_parent _ ->
    Code_error.raise "Expected a normal generated-rules result" []
;;

let%expect_test "empty generated rules retain subdirectory declarations" =
  let dir = Path.Build.relative Path.Build.root "default/generated" in
  let build_dir_only_sub_dirs =
    Gen_rules.Build_only_sub_dirs.singleton ~dir Subdir_set.empty
  in
  let declared = Gen_rules.make ~build_dir_only_sub_dirs (Memo.return Rules.empty) in
  List.iter
    [ "empty left", Gen_rules.no_rules, declared
    ; "empty right", declared, Gen_rules.no_rules
    ]
    ~f:(fun (name, left, right) ->
      let { Gen_rules.Rules.build_dir_only_sub_dirs; directory_targets; _ } =
        combine left right
      in
      printfn
        "%s: declaration=%b directory_targets_empty=%b"
        name
        (Path.Build.Map.mem build_dir_only_sub_dirs dir)
        (Path.Build.Map.is_empty directory_targets));
  [%expect
    {|
    empty left: declaration=true directory_targets_empty=true
    empty right: declaration=true directory_targets_empty=true
    |}]
;;

let source_dir = Path.Build.relative Path.Build.root "default/source"

let with_sources sources rules =
  Gen_rules.Rules
    (Gen_rules.Rules.create ~sources:(Path.Build.Map.singleton source_dir sources) rules)
;;

let%expect_test "source subdirectory metadata is combined without evaluating rules" =
  let calls = ref 0 in
  let declared name =
    with_sources
      (Filename.Map.empty, Filename.Array.Set.singleton (Filename.of_string_exn name))
      (Memo.of_thunk (fun () ->
         incr calls;
         Memo.return Rules.empty))
  in
  List.iter
    [ "empty left", Gen_rules.no_rules, declared "left"
    ; "empty right", declared "left", Gen_rules.no_rules
    ; "both declared", declared "left", declared "right"
    ]
    ~f:(fun (name, left, right) ->
      let { Gen_rules.Rules.sources; _ } = combine left right in
      let subdirs =
        Path.Build.Map.find_exn sources source_dir
        |> snd
        |> Filename.Array.Set.to_list
        |> List.map ~f:Filename.to_string
        |> String.concat ~sep:","
      in
      printfn "%s: subdirs=%s calls=%d" name subdirs !calls);
  [%expect
    {|
    empty left: subdirs=left calls=0
    empty right: subdirs=left calls=0
    both declared: subdirs=left,right calls=0
    |}]
;;

let%expect_test "source file inventories are combined" =
  let declared name =
    let file = Filename.of_string_exn name in
    let rule =
      let dst = Path.Build.relative_fname source_dir file in
      Rule.make
        ~targets:(Targets.File.create dst)
        (Action_builder.return (Action.Full.make (Action.write_file dst "")))
    in
    with_sources
      (Filename.Map.singleton file rule, Filename.Array.Set.empty)
      (Memo.return Rules.empty)
  in
  let { Gen_rules.Rules.sources; _ } = combine (declared "left") (declared "right") in
  let files, _ = Path.Build.Map.find_exn sources source_dir in
  printfn
    "files=%s"
    (Filename.Map.keys files |> Filename.L.to_string |> String.concat ~sep:",");
  [%expect {| files=left,right |}]
;;
