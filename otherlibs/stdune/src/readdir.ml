module File_kind = struct
  include File_kind

  module Option = struct
    [@@@warning "-37"]

    (* The values are constructed on the C-side *)
    type t =
      | S_REG
      | S_DIR
      | S_CHR
      | S_BLK
      | S_LNK
      | S_FIFO
      | S_SOCK
      | UNKNOWN

    let elim ~none ~some t =
      match t with
      | S_REG -> some (S_REG : Unix.file_kind)
      | S_DIR -> some S_DIR
      | S_CHR -> some S_CHR
      | S_BLK -> some S_BLK
      | S_LNK -> some S_LNK
      | S_FIFO -> some S_FIFO
      | S_SOCK -> some S_SOCK
      | UNKNOWN -> none ()
    ;;
  end
end

module Readdir_result = struct
  [@@@warning "-37"]

  (* The values are constructed on the C-side *)
  type t =
    | End_of_directory
    | Entry of string * File_kind.Option.t
end

external readdir_with_kind_if_available_unix
  :  Unix.dir_handle
  -> Readdir_result.t
  = "caml__dune_filesystem_stubs__readdir"

(* Read an entire directory using FindFirstFileW/FindNextFileW, returning
   UTF-8 filenames with correct file kinds (including reparse points as S_LNK).
   This bypasses OCaml's Unix.readdir which uses ANSI APIs and cannot handle
   filenames with characters outside the current code page. *)
external read_dir_with_kinds_win32
  :  string
  -> (string * Unix.file_kind) list
  = "caml__dune_filesystem_stubs__read_dir_with_kinds_win32"

external win32_unlink : string -> unit = "caml__dune_filesystem_stubs__win32_unlink"
external win32_rmdir : string -> unit = "caml__dune_filesystem_stubs__win32_rmdir"

let readdir_with_kind_if_available_win32 : Unix.dir_handle -> Readdir_result.t =
  fun dir ->
  (* This is only used by read_directory_exn on non-Windows. On Windows,
     read_directory_with_kinds_exn uses read_dir_with_kinds_win32 directly. *)
  match Unix.readdir dir with
  | exception End_of_file -> Readdir_result.End_of_directory
  | entry -> Entry (entry, File_kind.Option.UNKNOWN)
;;

let readdir_with_kind_if_available : Unix.dir_handle -> Readdir_result.t =
  Counter.incr Metrics.Directory_read.count;
  if Stdlib.Sys.win32
  then readdir_with_kind_if_available_win32
  else readdir_with_kind_if_available_unix
;;

let read_directory_with_kinds_exn dir_path =
  if Stdlib.Sys.win32
  then read_dir_with_kinds_win32 dir_path
  else (
    let dir = Unix.opendir dir_path in
    Fun.protect
      ~finally:(fun () -> Unix.closedir dir)
      (fun () ->
         let rec loop acc =
           match readdir_with_kind_if_available dir with
           | Entry (("." | ".."), _) -> loop acc
           | End_of_directory -> acc
           | Entry (base, kind) ->
             let k kind = loop ((base, kind) :: acc) in
             let skip () = loop acc in
             File_kind.Option.elim
               kind
               ~none:(fun () ->
                 match Unix.lstat (Filename.concat dir_path base) with
                 | exception Unix.Unix_error _ ->
                   (* File disappeared between readdir & lstat system calls.
                      Handle as if readdir never told us about it *)
                   skip ()
                 | stat -> k stat.st_kind)
               ~some:k
         in
         loop []))
;;

let read_directory_with_kinds dir_path =
  Unix_error.Detailed.catch read_directory_with_kinds_exn dir_path
;;

let read_directory_exn dir_path =
  if Stdlib.Sys.win32
  then List.map ~f:(fun (name, _) -> name) (read_dir_with_kinds_win32 dir_path)
  else (
    let dir = Unix.opendir dir_path in
    Fun.protect
      ~finally:(fun () -> Unix.closedir dir)
      (fun () ->
         let rec loop acc =
           match readdir_with_kind_if_available dir with
           | Entry (("." | ".."), _) -> loop acc
           | End_of_directory -> acc
           | Entry (base, _) -> loop (base :: acc)
         in
         loop []))
;;

let read_directory dir_path = Unix_error.Detailed.catch read_directory_exn dir_path
