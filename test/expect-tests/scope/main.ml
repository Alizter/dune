open Stdune
open Dune_engine
open Dune_rules
open Memo.O
module Workspace = Source.Workspace
module Dune_config = Dune_config_file.Dune_config
module Scheduler = Dune_scheduler.Scheduler

let%expect_test "package library entries and lazy native visibility" =
  let cwd = Path.External.cwd () in
  Temp.with_temp_dir
    ~parent_dir:(Path.external_ cwd)
    ~prefix:"scope-cache"
    ~suffix:""
    ~f:(fun dir ->
      let dir = Result.ok_exn dir in
      Exn.protect
        ~finally:(fun () -> Sys.chdir (Path.External.to_string cwd))
        ~f:(fun () ->
          Sys.chdir (Path.to_string dir);
          Dune_tests_common.init ();
          Global.init ~capture_outputs:false;
          Workspace.Clflags.set
            { Workspace.Clflags.x = None
            ; profile = None
            ; instrument_with = None
            ; workspace_file = None
            ; config_from_command_line = Dune_config.Partial.empty
            ; config_from_config_file = Dune_config.Partial.empty
            };
          Source.Only_packages.Clflags.set No_restriction;
          Memo.reset (Fs_memo.init ~dune_file_watcher:None);
          let write file = Io.write_file_exn (Path.relative Path.root file) in
          write
            "dune-project"
            "(lang dune 3.21)\n\
            \ (package (name a) (deprecated_package_names old-a))\n\
            \ (package (name b))\n";
          let write_stanzas names =
            let redirects =
              List.map names ~f:(fun name ->
                sprintf
                  "(deprecated_library_name (old_public_name old-a.%s)\n\
                  \ (new_public_name b.missing))\n"
                  name)
              |> String.concat ~sep:""
            in
            write
              "dune"
              (redirects
               ^ "(install (package a) (section share) (files missing))\n"
               ^ "(library (name unowned))\n"
               ^ "(library (public_name b)\n (enabled_if (= %{read:missing} true)))\n")
          in
          let run computation =
            Scheduler.Run.go
              { Scheduler.Config.concurrency = 1
              ; print_ctrl_c_warning = false
              ; watch_exclusions = []
              }
              ~file_watcher:No_watcher
              (fun () -> Memo.run computation)
          in
          let package = Dune_lang.Package.Name.of_string in
          let entries () =
            Scope.DB.lib_entries_of_package Context_name.default (package "a")
          in
          let package_stanzas name =
            Partitions.stanzas_of_package Context_name.default (package name)
          in
          let previous = Weak.create 1 in
          write_stanzas [ "old" ];
          run
            (let+ stanzas = package_stanzas "a"
             and+ other = package_stanzas "b"
             and+ deprecated = package_stanzas "old-a"
             and+ unknown = package_stanzas "unknown"
             and+ dune_files = Partitions.dune_files Context_name.default in
             let expected =
               List.concat_map dune_files ~f:Dune_file.static_stanzas
               |> List.filter ~f:(fun stanza ->
                 match Dune_lang.Stanza.repr stanza with
                 | Library.T _ -> false
                 | _ -> true)
             in
             printfn "indexed a stanzas: %d" (List.length stanzas);
             printfn "indexed b stanzas: %d" (List.length other);
             printfn
               "source order preserved: %b"
               (List.equal Dune_lang.Stanza.equal (List.map stanzas ~f:snd) expected);
             printfn "deprecated package bucket: %d" (List.length deprecated);
             printfn "unknown package bucket: %d" (List.length unknown));
          run
            (let+ entries = entries () in
             printfn
               "initial deprecated names: %d"
               (List.length entries.deprecated_library_names);
             Weak.set previous 0 (Some entries));
          write_stanzas [ "old"; "new" ];
          let invalidate () =
            Memo.reset
              (Memo.Invalidation.invalidate_caches ~reason:Memo.Invalidation.Reason.Test)
          in
          invalidate ();
          run
            (let+ entries = entries () in
             printfn
               "updated deprecated names: %d"
               (List.length entries.deprecated_library_names));
          Gc.full_major ();
          printfn "obsolete entries retained: %b" (Weak.check previous 0);
          Config.init String.Map.empty;
          Execution_parameters.init (Memo.return Execution_parameters.builtin_default);
          Main.init ~sandbox_actions:false ~sandboxing_preference:[] ();
          write
            "dune-project"
            "(lang dune 3.25)\n(package (name app) (dir .) (depends declared))\n";
          write "dune" "(library (public_name app) (modules))\n";
          Path.mkdir_p (Path.relative Path.root "dune.lock");
          write
            "dune.lock/lock.dune"
            "(lang package 0.1)\n(repositories (complete true))\n";
          write
            "dune.lock/declared.pkg"
            "(version 1.0)\n\
            \ (build (progn (write-file META \"version = \\\"1\\\"\\n\")\n\
            \ (write-file declared.install \"lib: [ \\\"META\\\" ]\")))\n";
          write "dune.lock/hidden.pkg" "(version 1.0)\n(build (run false))\n";
          Path.mkdir_p (Path.relative Path.root "_native");
          write "_native/dune-project" "(lang dune 3.25)\n(package (name native))\n";
          write
            "_native/dune"
            "(library (name implementation) (public_name native)\n\
            \ (modules exported))\n\
            \ (library (name private_impl) (modules private_mod))\n";
          List.iter [ "exported"; "private_mod" ] ~f:(fun name ->
            write ("_native/" ^ name ^ ".ml") "");
          write
            "dune.lock/native.pkg"
            (sprintf
               "(version 1.0)\n(source (copy %S))\n(build (run false))\n"
               (Path.to_absolute_filename (Path.relative Path.root "_native")));
          run
            (Fs_memo.dir_contents
               ~force_update:true
               (Path.Outside_build_dir.In_source_dir Path.Source.root)
             |> Memo.map ~f:ignore);
          invalidate ();
          run
            (let* scope =
               Scope.DB.find_by_dir (Context_name.build_dir Context_name.default)
             in
             let db = Scope.public_libs scope in
             let* dune_files =
               Partitions.dune_files_of_package Context_name.default (package "native")
             in
             let ids =
               Dune_file.fold_static_stanzas
                 dune_files
                 ~init:String.Map.empty
                 ~f:(fun dune_file stanza ids ->
                   match Dune_lang.Stanza.repr stanza with
                   | Library.T library ->
                     let id =
                       Library.to_lib_id ~src_dir:(Dune_file.dir dune_file) library
                     in
                     String.Map.set
                       ids
                       (Dune_lang.Lib_name.to_string (Lib_id.Local.name id))
                       (Lib_id.Local id)
                   | _ -> ids)
             in
             let visible name =
               Lib.DB.find_lib_id db (String.Map.find_exn ids name) >>| Option.is_some
             in
             let* public = visible "implementation" in
             printfn "undeclared native local id: %b" public;
             let* private_ = visible "private_impl" in
             printfn "private local id visible: %b" private_;
             let owned = String.Set.of_list [ "app"; "declared"; "native"; "hidden" ] in
             let+ libraries = Lib.DB.all db in
             let names =
               Lib.Set.to_list libraries
               |> List.map ~f:(fun lib -> Dune_lang.Lib_name.to_string (Lib.name lib))
               |> List.filter ~f:(String.Set.mem owned)
               |> List.sort ~compare:String.compare
             in
             printfn "owned public enumeration: %s" (String.concat ~sep:", " names);
             let ran name =
               Stdlib.Sys.file_exists
                 (sprintf "_build/default/.pkg/%s/_install/cookie" name)
             in
             printfn "declared opaque recipe ran: %b" (ran "declared");
             printfn "undeclared opaque recipe ran: %b" (ran "hidden"))));
  [%expect
    {|
    indexed a stanzas: 2
    indexed b stanzas: 1
    source order preserved: true
    deprecated package bucket: 0
    unknown package bucket: 0
    initial deprecated names: 1
    updated deprecated names: 2
    obsolete entries retained: false
    undeclared native local id: true
    private local id visible: false
    owned public enumeration: app, declared, native
    declared opaque recipe ran: true
    undeclared opaque recipe ran: false
    |}]
;;
