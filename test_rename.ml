let () =
  Dune_patch.For_tests.parse_patches
    ~loc:Loc.none
    {|
diff --git a/old.ml b/new.ml  
similarity index 100%
rename from old.ml
rename to new.ml
|}
  |> List.iter (fun p ->
    Printf.printf
      "%s\n"
      (Dyn.to_string (Dune_patch.For_tests.Patch.operation_to_dyn p.operation)))
;;
