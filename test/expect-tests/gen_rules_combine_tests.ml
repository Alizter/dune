open Stdune
open Dune_engine
module Generated_rules = Build_config.Gen_rules.Rules

let () = Dune_tests_common.init ()

let run rules =
  Fiber.run (Memo.run rules) ~iter:(fun () ->
    Code_error.raise "Unexpected suspension in generated rules test" [])
;;

let%expect_test "empty generated rule combinations remain deferred" =
  let calls = ref 0 in
  let effectful =
    Generated_rules.create
      ~source_sub_dirs:Path.Build.Map.empty
      ~source_files:Path.Build.Map.empty
      (Memo.of_thunk (fun () ->
         incr calls;
         Memo.return Rules.empty))
  in
  List.iter
    [ "both empty", Generated_rules.empty, Generated_rules.empty
    ; "empty left", Generated_rules.empty, effectful
    ; "empty right", effectful, Generated_rules.empty
    ; "same effectful record", effectful, effectful
    ]
    ~f:(fun (name, left, right) ->
      calls := 0;
      let { Generated_rules.rules; _ } = Generated_rules.combine_exn left right in
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

let%expect_test "empty generated rules retain subdirectory declarations" =
  let dir = Path.Build.relative Path.Build.root "default/generated" in
  let build_dir_only_sub_dirs =
    Build_config.Gen_rules.Build_only_sub_dirs.singleton ~dir Subdir_set.empty
  in
  let declared =
    Generated_rules.create
      ~build_dir_only_sub_dirs
      ~source_sub_dirs:Path.Build.Map.empty
      ~source_files:Path.Build.Map.empty
      (Memo.return Rules.empty)
  in
  List.iter
    [ "empty left", Generated_rules.empty, declared
    ; "empty right", declared, Generated_rules.empty
    ]
    ~f:(fun (name, left, right) ->
      let { Generated_rules.build_dir_only_sub_dirs; directory_targets; _ } =
        Generated_rules.combine_exn left right
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

let%expect_test "source subdirectory metadata is combined without evaluating rules" =
  let dir = Path.Build.relative Path.Build.root "default/source" in
  let calls = ref 0 in
  let declared name =
    Generated_rules.create
      ~source_sub_dirs:
        (Path.Build.Map.singleton
           dir
           (Filename.Set.singleton (Filename.of_string_exn name)))
      ~source_files:Path.Build.Map.empty
      (Memo.of_thunk (fun () ->
         incr calls;
         Memo.return Rules.empty))
  in
  let left = declared "left" in
  let right = declared "right" in
  List.iter
    [ "empty left", Generated_rules.empty, left
    ; "empty right", left, Generated_rules.empty
    ; "both declared", left, right
    ]
    ~f:(fun (name, left, right) ->
      let { Generated_rules.source_sub_dirs; _ } =
        Generated_rules.combine_exn left right
      in
      let subdirs =
        Path.Build.Map.find_exn source_sub_dirs dir
        |> Filename.Set.to_list
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

let%expect_test "source file inventories do not force materialization" =
  let dir = Path.Build.relative Path.Build.root "default/source" in
  let calls = ref 0 in
  let declared name =
    let file = Filename.of_string_exn name in
    let materialization =
      Memo.of_thunk (fun () ->
        incr calls;
        Load_rules.source_file_copy
          ~src:(Path.Source.relative_fname Path.Source.root file)
          ~dst:(Path.Build.relative_fname dir file)
        |> Memo.return)
    in
    Generated_rules.create
      ~source_sub_dirs:Path.Build.Map.empty
      ~source_files:
        (Path.Build.Map.singleton dir (Filename.Map.singleton file materialization))
      (Memo.return Rules.empty)
  in
  let { Generated_rules.source_files; _ } =
    Generated_rules.combine_exn (declared "left") (declared "right")
  in
  let files = Path.Build.Map.find_exn source_files dir in
  printfn
    "files=%s calls=%d"
    (Filename.Map.keys files |> Filename.L.to_string |> String.concat ~sep:",")
    !calls;
  let (_ : Rule.t) = run (Filename.Map.find_exn files (Filename.of_string_exn "left")) in
  printfn "after selecting left: calls=%d" !calls;
  [%expect
    {|
    files=left,right calls=0
    after selecting left: calls=1
    |}]
;;
