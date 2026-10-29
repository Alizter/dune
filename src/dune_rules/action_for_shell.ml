open Import

let rec encode (action : Action.t) ~dir =
  let module Outputs = Dune_lang.Action.Outputs in
  let module File_perm = Dune_lang.Action.File_perm in
  let module Inputs = Dune_lang.Action.Inputs in
  let open Dune_sexp in
  let string = Encoder.string in
  let path p = string (Path.reach p ~from:dir) in
  let target p = path (Path.build p) in
  let program = function
    | Ok p -> string (Path.reach_for_running p ~from:dir)
    | Error { Action.Prog.Not_found.context; program; hint; loc = _ } ->
      List
        (atom "unresolved-program"
         :: string (Context_name.to_string context)
         :: string (Filename.to_string program)
         :: Option.to_list (Option.map hint ~f:string))
  in
  let loop = encode ~dir in
  match action with
  | Run { prog; args; can_run_in_action_runner = _ } ->
    List (atom "run" :: program prog :: List.map (Appendable_list.to_list args) ~f:string)
  | With_accepted_exit_codes (pred, action) ->
    List
      [ atom "with-accepted-exit-codes"
      ; Predicate_lang.encode Dune_sexp.Encoder.int pred
      ; loop action
      ]
  | Chdir (chdir, action) -> List [ atom "chdir"; path chdir; encode action ~dir:chdir ]
  | Setenv (var, value, action) ->
    List [ atom "setenv"; string var; string value; loop action ]
  | Redirect_out (outputs, file, perm, action) ->
    List
      [ atom (sprintf "with-%s-to%s" (Outputs.to_string outputs) (File_perm.suffix perm))
      ; target file
      ; loop action
      ]
  | Redirect_in (inputs, file, action) ->
    List
      [ atom (sprintf "with-%s-from" (Inputs.to_string inputs)); path file; loop action ]
  | Ignore (outputs, action) ->
    List [ atom (sprintf "ignore-%s" (Outputs.to_string outputs)); loop action ]
  | Progn actions -> List (atom "progn" :: List.map actions ~f:loop)
  | Concurrent actions -> List (atom "concurrent" :: List.map actions ~f:loop)
  | Echo strings -> List (atom "echo" :: List.map strings ~f:string)
  | Cat paths -> List (atom "cat" :: List.map paths ~f:path)
  | Copy (src, dst) -> List [ atom "copy"; path src; target dst ]
  | Symlink (src, dst) ->
    let src =
      match Path.Build.parent dst with
      | None -> Path.to_string src
      | Some from -> Path.reach src ~from:(Path.build from)
    in
    List [ atom "symlink"; string src; target dst ]
  | Hardlink (src, dst) -> List [ atom "hardlink"; path src; target dst ]
  | System command -> List [ atom "system"; string command ]
  | Bash { script; can_run_in_action_runner = _ } -> List [ atom "bash"; string script ]
  | Write_file (file, perm, contents) ->
    List [ atom ("write-file" ^ File_perm.suffix perm); target file; string contents ]
  | Rename (src, dst) -> List [ atom "rename"; target src; target dst ]
  | Remove_tree file -> List [ atom "remove-tree"; target file ]
  | Mkdir dir -> List [ atom "mkdir"; target dir ]
  | Pipe (outputs, actions) ->
    List (atom (sprintf "pipe-%s" (Outputs.to_string outputs)) :: List.map actions ~f:loop)
  | Diff { optional; file1; file2; mode; directory_diffs } ->
    let name =
      match mode, optional, directory_diffs with
      | Binary, false, true -> "cmp"
      | Binary, false, false -> "cmp-no-directory"
      | Binary, true, _ -> Code_error.raise "optional binary diff in shell action" []
      | Text, false, true -> "diff"
      | Text, true, true -> "diff?"
      | Text, false, false -> "diff-no-directory"
      | Text, true, false -> "diff-no-directory?"
    in
    List [ atom name; path file1; target file2 ]
  | Extension _ -> Code_error.raise "action extension passed to shell encoder" []
;;

let decode ~session_root ~dir =
  let normalize_absolute path =
    match String.drop_prefix path ~prefix:"/" with
    | None ->
      Code_error.raise
        "dune shell replay expected an absolute POSIX path"
        [ "path", Dyn.string path ]
    | Some path ->
      Path.Local.of_string path
      |> Path.Local.to_string
      |> Path.External.relative Path.External.root
  in
  let resolve ~dir path =
    let absolute =
      if Filename.is_relative path
      then
        Path.External.relative
          (Path.External.of_string (Path.to_absolute_filename dir))
          path
      else Path.External.of_string path
    in
    normalize_absolute (Path.External.to_string absolute) |> Path.external_
  in
  let rec decode ~dir =
    let open Dune_lang.Decoder in
    let* loc = loc in
    let checked_path value =
      let resolved = resolve ~dir value in
      let localized = Path.Expert.try_localize_external resolved in
      match Path.as_in_build_dir localized with
      | None -> resolved
      | Some _ ->
        if
          Path.equal localized session_root
          || Path.is_descendant localized ~of_:session_root
        then localized
        else
          User_error.raise
            ~loc
            [ Pp.textf
                "Edited action path %s escapes the dune shell session."
                (Path.to_string_maybe_quoted localized)
            ]
    in
    let path =
      let+ value = string in
      let checked = checked_path value in
      (* Preserve filesystem resolution of absolute symlink/.. operands after
         checking the normalized session boundary. *)
      if Filename.is_relative value then checked else Path.of_string value
    in
    let target =
      let+ value = string in
      let checked = checked_path value in
      match Path.as_in_build_dir checked with
      | Some target -> target
      | None ->
        User_error.raise
          ~loc
          [ Pp.textf
              "Edited action target %s is outside the dune shell session."
              (Path.to_string_maybe_quoted checked)
          ]
    in
    let program =
      enter
      @@ sum
           [ ( "unresolved-program"
             , let+ context = string
               and+ program = string
               and+ hint = repeat string in
               let hint =
                 match hint with
                 | [] -> None
                 | [ hint ] -> Some hint
                 | _ ->
                   User_error.raise
                     [ Pp.text
                         "An unresolved-program accepts at most one diagnostic hint."
                     ]
               in
               let program =
                 match Filename.of_string program with
                 | Some program -> program
                 | None ->
                   User_error.raise
                     [ Pp.text "Invalid program name in unresolved-program." ]
               in
               Error
                 (Action.Prog.Not_found.create
                    ?hint
                    ~context:(Context_name.of_string context)
                    ~program
                    ~loc:(Some loc)
                    ()) )
           ]
      <|> (path >>| fun path -> Ok path)
    in
    let action = decode ~dir in
    let redirect_out outputs perm =
      let+ file = target
      and+ action = action in
      Action.Redirect_out (outputs, file, perm, action)
    in
    let write_file perm =
      let+ file = target
      and+ contents = string in
      Action.Write_file (file, perm, contents)
    in
    let pipe outputs =
      let+ first = action
      and+ second = action
      and+ rest = repeat action in
      Action.Pipe (outputs, first :: second :: rest)
    in
    let diff ~optional ~mode ~directory_diffs =
      let+ file1 = path
      and+ file2 = target in
      Action.Diff { optional; mode; file1; file2; directory_diffs }
    in
    sum
      [ ( "run"
        , let+ prog = program
          and+ args = repeat string in
          Action.Run
            { prog
            ; args = Appendable_list.of_list args
            ; can_run_in_action_runner = false
            } )
      ; ( "with-accepted-exit-codes"
        , let+ codes = Predicate_lang.decode_one int
          and+ action = action in
          Action.With_accepted_exit_codes (codes, action) )
      ; ( "chdir"
        , let* chdir = string in
          let chdir = checked_path chdir in
          if
            not
              (Path.equal chdir session_root || Path.is_descendant chdir ~of_:session_root)
          then
            User_error.raise
              ~loc
              [ Pp.text "Edited action chdir escapes the dune shell session." ];
          let+ action = decode ~dir:chdir in
          Action.Chdir (chdir, action) )
      ; ( "setenv"
        , let+ var = string
          and+ value = string
          and+ action = action in
          Action.Setenv (var, value, action) )
      ; "with-stdout-to", redirect_out Stdout Normal
      ; "with-stdout-to-executable", redirect_out Stdout Executable
      ; "with-stderr-to", redirect_out Stderr Normal
      ; "with-stderr-to-executable", redirect_out Stderr Executable
      ; "with-outputs-to", redirect_out Outputs Normal
      ; "with-outputs-to-executable", redirect_out Outputs Executable
      ; ( "with-stdin-from"
        , let+ file = path
          and+ action = action in
          Action.Redirect_in (Stdin, file, action) )
      ; ("ignore-stdout", action >>| fun action -> Action.Ignore (Stdout, action))
      ; ("ignore-stderr", action >>| fun action -> Action.Ignore (Stderr, action))
      ; ("ignore-outputs", action >>| fun action -> Action.Ignore (Outputs, action))
      ; "progn", repeat action >>| Action.progn
      ; "concurrent", repeat action >>| Action.concurrent
      ; "echo", repeat string >>| Action.echo
      ; "cat", repeat path >>| Action.cat
      ; ( "copy"
        , let+ src = path
          and+ dst = target in
          Action.Copy (src, dst) )
      ; ( "symlink"
        , let+ source = string
          and+ target = target in
          let source_dir = Path.build (Path.Build.parent_exn target) in
          let source =
            if Filename.is_relative source
            then resolve ~dir:source_dir source |> Path.Expert.try_localize_external
            else Path.of_string source
          in
          Action.Symlink (source, target) )
      ; ( "hardlink"
        , let+ src = path
          and+ dst = target in
          Action.Hardlink (src, dst) )
      ; ("system", string >>| fun command -> Action.System command)
      ; ( "bash"
        , string
          >>| fun script -> Action.Bash { script; can_run_in_action_runner = false } )
      ; "write-file", write_file Normal
      ; "write-file-executable", write_file Executable
      ; ( "rename"
        , let+ src = target
          and+ dst = target in
          Action.Rename (src, dst) )
      ; "remove-tree", target >>| Action.remove_tree
      ; "mkdir", target >>| Action.mkdir
      ; "pipe-stdout", pipe Stdout
      ; "pipe-stderr", pipe Stderr
      ; "pipe-outputs", pipe Outputs
      ; "diff", diff ~optional:false ~mode:Text ~directory_diffs:true
      ; "diff?", diff ~optional:true ~mode:Text ~directory_diffs:true
      ; "diff-no-directory", diff ~optional:false ~mode:Text ~directory_diffs:false
      ; "diff-no-directory?", diff ~optional:true ~mode:Text ~directory_diffs:false
      ; "cmp", diff ~optional:false ~mode:Binary ~directory_diffs:true
      ; "cmp-no-directory", diff ~optional:false ~mode:Binary ~directory_diffs:false
      ; ( "ext"
        , let+ (_ : string) = string in
          User_error.raise
            [ Pp.text "Edited extension actions cannot be replayed."
            ; Pp.text
                "Restore action.sexp and edit the underlying dune file instead; action \
                 extensions do not provide an inverse decoder."
            ] )
      ]
  in
  decode ~dir
;;
