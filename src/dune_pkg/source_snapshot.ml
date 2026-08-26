open Import
open Dune_scheduler

module Archive = struct
  type t =
    { path : Path.t
    ; filename : Filename.t
    ; digest : Dune_digest.t
    }
end

type t =
  { id : Dune_digest.t
  ; root : Path.t
  ; directories : [ `Dir | `File ] Filename.Map.t Path.Local.Map.t
  ; manifest_digest : Dune_digest.t
  }

let id t = t.id
let manifest_digest t = t.manifest_digest

let readdir t path =
  Path.Local.Map.find t.directories path
  |> Option.value ~default:Filename.Map.empty
  |> Memo.return
;;

let read_file t path =
  Path.append_local t.root path |> Io.read_file ~binary:true |> Memo.return
;;

let file_path t path = Path.append_local t.root path

let cache_root =
  lazy (Path.L.relative (Lazy.force Dune_util.cache_root_dir) [ "pkg-sources"; "v1" ])
;;

let rec acquire_lock flock ~attempts =
  match Flock.lock_non_block flock Flock.Exclusive with
  | Ok `Success -> Fiber.return ()
  | Ok `Failure when attempts > 0 ->
    let open Fiber.O in
    let* () = Scheduler.sleep (Time.Span.of_secs 0.1) in
    acquire_lock flock ~attempts:(attempts - 1)
  | Ok `Failure ->
    User_error.raise [ Pp.text "Timed out waiting for a mounted source snapshot lock." ]
  | Error error ->
    User_error.raise
      [ Pp.textf "Unable to lock mounted source snapshot: %s" (Unix.error_message error) ]
;;

let with_lock path ~f =
  let open Fiber.O in
  let fd =
    Unix.openfile
      (Path.to_string path)
      [ Unix.O_CREAT; O_WRONLY; O_SHARE_DELETE; Unix.O_CLOEXEC ]
      0o600
    |> Fd.unsafe_of_unix_file_descr
  in
  let flock = Flock.create fd in
  Fiber.finalize
    ~finally:(fun () ->
      let+ () = Fiber.return () in
      Fd.close fd)
    (fun () ->
       let* () = acquire_lock flock ~attempts:300 in
       Fiber.finalize f ~finally:(fun () ->
         let+ () = Fiber.return () in
         match Flock.unlock flock with
         | Ok () -> ()
         | Error error ->
           Unix_error.Detailed.create error ~syscall:"flock" ~arg:"unlock"
           |> Unix_error.Detailed.raise))
;;

let unable_to_resolve path =
  User_error.raise
    [ Pp.textf
        "Unable to resolve symlink in mounted package source: %s"
        (Path.to_string_maybe_quoted path)
    ]
;;

let scan root =
  let root_real =
    match Unix.realpath (Path.to_string root) with
    | path -> path
    | exception Unix.Unix_error _ -> unable_to_resolve root
  in
  let inside_root path =
    String.equal path root_real
    || String.starts_with path ~prefix:(root_real ^ Filename.dir_sep)
  in
  let resolve path =
    let real =
      match Unix.realpath (Path.to_string path) with
      | path -> path
      | exception Unix.Unix_error _ -> unable_to_resolve path
    in
    if not (inside_root real) then unable_to_resolve path;
    real
  in
  let unsupported path =
    User_error.raise
      [ Pp.textf
          "Unsupported file in mounted package source: %s"
          (Path.to_string_maybe_quoted path)
      ]
  in
  let rec loop dir local stack directories manifest =
    let real = resolve dir in
    if String.Set.mem stack real then unable_to_resolve dir;
    let stack = String.Set.add stack real in
    let entries =
      match Path.readdir_unsorted_with_kinds dir with
      | Ok entries ->
        List.sort entries ~compare:(fun (a, _) (b, _) -> Filename.compare a b)
      | Error error -> Unix_error.Detailed.raise error
    in
    let entries =
      List.map entries ~f:(fun (name, file_kind) ->
        let path = Path.relative_fname dir name in
        let local_path = Path.Local.relative_fname local name in
        let stats, symlink =
          match file_kind with
          | Unix.S_LNK ->
            let _ = resolve path in
            let stats =
              match Unix.stat (Path.to_string path) with
              | stats -> stats
              | exception Unix.Unix_error _ -> unable_to_resolve path
            in
            stats, Some (Unix.readlink (Path.to_string path))
          | _ -> Unix.lstat (Path.to_string path), None
        in
        let kind =
          match stats.st_kind with
          | S_REG -> `File
          | S_DIR -> `Dir
          | S_LNK | S_CHR | S_BLK | S_FIFO | S_SOCK -> unsupported path
        in
        let mode = stats.st_perm land 0o777 in
        let path_string = Path.Local.to_string local_path in
        let symlink =
          match symlink with
          | None -> ""
          | Some target -> sprintf " link=%S" target
        in
        let manifest_line =
          match kind with
          | `Dir -> sprintf "d %03o %s%s" mode path_string symlink
          | `File ->
            sprintf
              "f %03o %s %s%s"
              mode
              (Dune_digest.file path |> Dune_digest.to_string)
              path_string
              symlink
        in
        name, kind, manifest_line)
    in
    let entry_map =
      List.map entries ~f:(fun (name, kind, _) -> name, kind) |> Filename.Map.of_list_exn
    in
    let directories = Path.Local.Map.set directories local entry_map in
    List.fold_left
      entries
      ~init:(directories, manifest)
      ~f:(fun (directories, manifest) (name, kind, manifest_line) ->
        let manifest = manifest_line :: manifest in
        match kind with
        | `File -> directories, manifest
        | `Dir ->
          loop
            (Path.relative_fname dir name)
            (Path.Local.relative_fname local name)
            stack
            directories
            manifest)
  in
  let root_mode = (Unix.stat (Path.to_string root)).st_perm land 0o777 in
  let directories, manifest =
    loop
      root
      Path.Local.root
      String.Set.empty
      Path.Local.Map.empty
      [ sprintf "root %03o" root_mode ]
  in
  let manifest = List.rev manifest |> String.concat ~sep:"\n" in
  directories, Dune_digest.string manifest, manifest
;;

let make ~id ~root ~directories ~manifest_digest =
  { id; root; directories; manifest_digest }
;;

let load ~id entry =
  let root = Path.relative entry "root" in
  if not (Fpath.exists (Path.to_string root))
  then None
  else (
    let directories, manifest_digest, manifest = scan root in
    let manifest_file = Path.relative entry "manifest" in
    if
      (not (Fpath.exists (Path.to_string manifest_file)))
      || not (String.equal manifest (Io.read_file manifest_file))
    then
      User_error.raise
        [ Pp.textf
            "Invalid mounted source snapshot cache entry: %s"
            (Path.to_string_maybe_quoted entry)
        ; Pp.text "Remove this entry and retry the build."
        ];
    Some (make ~id ~root ~directories ~manifest_digest))
;;

let prepare_impl ({ Archive.path = archive; filename; digest } : Archive.t) =
  let id = Dune_digest.string ("source-snapshot-v1:" ^ Dune_digest.to_string digest) in
  let base = Lazy.force cache_root in
  let entry = Path.relative base (Dune_digest.to_string id) in
  match load ~id entry with
  | Some snapshot -> Memo.return snapshot
  | None ->
    Memo.of_reproducible_fiber
    @@
    let open Fiber.O in
    let* () = Fiber.return () in
    Path.mkdir_p base;
    let lock = Path.relative base (Dune_digest.to_string id ^ ".lock") in
    with_lock lock ~f:(fun () ->
      match load ~id entry with
      | Some snapshot -> Fiber.return snapshot
      | None ->
        let temp =
          Temp.temp_in_dir
            Dir
            ~dir:base
            ~prefix:(Dune_digest.to_string id)
            ~suffix:"snapshot"
        in
        Fiber.finalize
          ~finally:(fun () ->
            Path.rm_rf ~allow_external:true temp;
            Fiber.return ())
          (fun () ->
             let root = Path.relative temp "root" in
             let driver =
               Archive_driver.choose_for_filename_default_to_tar
                 (Filename.to_string filename)
             in
             let* () =
               Archive_driver.extract driver ~archive ~target:root
               >>| function
               | Ok () -> ()
               | Error () ->
                 User_error.raise
                   [ Pp.textf
                       "Unable to extract mounted package archive %s"
                       (Path.to_string_maybe_quoted archive)
                   ]
             in
             let directories, manifest_digest, manifest = scan root in
             Io.write_file (Path.relative temp "manifest") manifest;
             Unix.rename (Path.to_string temp) (Path.to_string entry);
             Fiber.return
               (make ~id ~root:(Path.relative entry "root") ~directories ~manifest_digest)))
;;

let prepare = prepare_impl
