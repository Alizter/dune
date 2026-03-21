open Import

let max_path = 260
let manifest_cache = Table.create (module Path) 64
let warned_progs = Table.create (module Path) 64
let warned_registry = ref false
let registry_cache = ref None

let long_paths_enabled () =
  if not Sys.win32
  then true
  else (
    match !registry_cache with
    | Some v -> v
    | None ->
      let v =
        match Sys.getenv "DUNE_LONG_PATH_ENABLED" with
        | "true" -> true
        | "false" -> false
        | _ -> Platform.long_paths_enabled_registry ()
        | exception Not_found -> Platform.long_paths_enabled_registry ()
      in
      registry_cache := Some v;
      v)
;;

let string_contains ~haystack ~needle =
  let hlen = String.length haystack in
  let nlen = String.length needle in
  if nlen = 0
  then true
  else if nlen > hlen
  then false
  else (
    let last = hlen - nlen in
    let found = ref false in
    let i = ref 0 in
    while !i <= last && not !found do
      if String.sub haystack ~pos:!i ~len:nlen = needle then found := true;
      incr i
    done;
    !found)
;;

let read_le_uint32 s off =
  Char.code (String.get s off)
  lor (Char.code (String.get s (off + 1)) lsl 8)
  lor (Char.code (String.get s (off + 2)) lsl 16)
  lor (Char.code (String.get s (off + 3)) lsl 24)
;;

let check_pe_manifest prog =
  let result =
    try
      let contents = Io.read_file ~binary:true prog in
      let len = String.length contents in
      if len < 64
      then false
      else if
        not
          (Char.equal (String.get contents 0) 'M'
           && Char.equal (String.get contents 1) 'Z')
      then false
      else (
        let pe_offset = read_le_uint32 contents 0x3C in
        if pe_offset + 4 > len
        then false
        else if
          not
            (Char.equal (String.get contents pe_offset) 'P'
             && Char.equal (String.get contents (pe_offset + 1)) 'E'
             && Char.equal (String.get contents (pe_offset + 2)) '\000'
             && Char.equal (String.get contents (pe_offset + 3)) '\000')
        then false
        else
          string_contains ~haystack:contents ~needle:"longPathAware"
          && string_contains ~haystack:contents ~needle:">true</longPathAware>")
    with
    | exn ->
      Log.info
        "Long_path_check.check_pe_manifest failed"
        [ "prog", Path.to_dyn prog; "exn", Dyn.string (Printexc.to_string exn) ];
      false
  in
  Log.info
    "Long_path_check.check_pe_manifest"
    [ "prog", Path.to_dyn prog; "result", Dyn.bool result ];
  result
;;

let has_long_path_manifest ~prog =
  if not Sys.win32
  then true
  else (
    match Table.find manifest_cache prog with
    | Some v -> v
    | None ->
      let v = check_pe_manifest prog in
      Table.set manifest_cache prog v;
      v)
;;

let char_is_alpha c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')

let string_contains_char s c =
  let len = String.length s in
  let found = ref false in
  let i = ref 0 in
  while !i < len && not !found do
    if Char.equal (String.get s !i) c then found := true;
    incr i
  done;
  !found
;;

let looks_like_path arg = string_contains_char arg '/' || string_contains_char arg '\\'

let effective_length ~dir arg =
  if
    (String.length arg >= 2
     && char_is_alpha (String.get arg 0)
     && Char.equal (String.get arg 1) ':')
    || (String.length arg >= 2
        && Char.equal (String.get arg 0) '\\'
        && Char.equal (String.get arg 1) '\\')
  then String.length arg
  else (
    match dir with
    | Some d -> String.length (Path.to_string d) + 1 + String.length arg
    | None -> String.length arg)
;;

let find_long_arg ~dir ~args =
  List.find args ~f:(fun arg ->
    looks_like_path arg && effective_length ~dir arg > max_path)
;;

let check_and_warn ~prog ~dir ~args =
  if not Sys.win32
  then ()
  else (
    Log.info
      "Long_path_check.check_and_warn"
      [ "prog", Path.to_dyn prog
      ; "nargs", Dyn.int (List.length args)
      ; ( "max_arg_len"
        , Dyn.int
            (List.fold_left args ~init:0 ~f:(fun acc a -> max acc (String.length a))) )
      ];
    match find_long_arg ~dir ~args with
    | None -> ()
    | Some long_arg ->
      if (not !warned_registry) && not (long_paths_enabled ())
      then (
        warned_registry := true;
        User_warning.emit
          [ Pp.textf
              "Path %S exceeds the Windows MAX_PATH limit of %d characters."
              long_arg
              max_path
          ; Pp.text "The LongPathsEnabled registry key does not appear to be set."
          ; Pp.text "Enable it with:"
          ; Pp.verbatim
              {|  reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled /t REG_DWORD /d 1 /f|}
          ]);
      if has_long_path_manifest ~prog
      then ()
      else (
        match Table.find warned_progs prog with
        | Some () -> ()
        | None ->
          Table.set warned_progs prog ();
          let prog_name = Path.to_string prog in
          User_warning.emit
            [ Pp.textf
                "%s does not appear to support long paths, but dune is passing a path of \
                 %d characters. The build may fail unless %s has a longPathAware \
                 manifest or LongPathsEnabled is set system-wide."
                prog_name
                (effective_length ~dir long_arg)
                prog_name
            ]))
;;
