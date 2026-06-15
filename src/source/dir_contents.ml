open Import
open Memo.O

module File = struct
  module T = struct
    type t =
      { ino : int
      ; dev : int
      }

    let repr =
      Repr.record
        "dir-contents-file"
        [ Repr.field "ino" Repr.int ~get:(fun t -> t.ino)
        ; Repr.field "dev" Repr.int ~get:(fun t -> t.dev)
        ]
    ;;

    let to_dyn = Repr.to_dyn repr

    include Repr.Poly (struct
        type nonrec t = t

        let repr = repr
      end)
  end

  include T

  let dummy = { ino = 0; dev = 0 }
  let of_stats (st : Fs_memo.Reduced_stats.t) = { ino = st.st_ino; dev = st.st_dev }

  module Map = Map.Make (T)

  let of_path p = Fs_memo.path_stat p >>| Result.map ~f:of_stats
  let of_source_path p = of_path (Path.Outside_build_dir.In_source_dir p)
end

type t =
  { files : Filename.Array.Set.t
  ; dirs : File.t Filename.Array.Map.t
  }

let files t = t.files
let dirs t = t.dirs

let equal x y =
  Filename.Array.Set.equal x.files y.files
  && Filename.Array.Map.equal x.dirs y.dirs ~equal:(fun f1 f2 -> File.compare f1 f2 = Eq)
;;

let empty = { files = Filename.Array.Set.empty; dirs = Filename.Array.Map.empty }
let make ~files ~dirs = { files; dirs }

let to_dyn { files; dirs } =
  let open Dyn in
  record
    [ "files", Set (Filename.Array.Set.to_list_map files ~f:Filename.to_dyn)
    ; ( "dirs"
      , list
          (pair string File.to_dyn)
          (Filename.Array.Map.to_list_map dirs ~f:(fun name file ->
             Filename.to_string name, file)) )
    ]
;;

(* Returns [true] for special files such as character devices of sockets; see
   #3124 for more on issues caused by special devices *)
let is_special (st_kind : Unix.file_kind) =
  match st_kind with
  | S_CHR | S_BLK | S_FIFO | S_SOCK -> true
  | _ -> false
;;

let is_temp_file fn =
  let fn = Filename.to_string fn in
  String.starts_with ~prefix:".#" fn
  || String.ends_with ~suffix:".swp" fn
  || String.ends_with ~suffix:"~" fn
;;

(* [path_for_hint] is the [Path.Source.t] identity of the directory being
   read, used for the "(dirs \ ...) hint" in the diagnostic. [physical] is
   the actual location the bytes are read from. For the workspace root
   these coincide; for an externally-rooted source tree they differ. *)
let of_outside_build_dir_impl ~path_for_hint ~physical =
  Fs_memo.dir_contents physical
  >>= function
  | Error unix_error ->
    User_warning.emit
      [ Pp.textf
          "Unable to read directory %s. Ignoring."
          (Path.Source.to_string_maybe_quoted path_for_hint)
      ; Pp.text "Remove this message by ignoring by adding:"
      ; Pp.textf "(dirs \\ %s)" (Path.Source.basename path_for_hint |> Filename.to_string)
      ; Pp.textf
          "to the dune file: %s"
          (Path.Source.to_string_maybe_quoted
             (Path.Source.relative (Path.Source.parent_exn path_for_hint) "dune"))
      ; Unix_error.Detailed.pp_reason unix_error
      ];
    Memo.return (Error unix_error)
  | Ok dir_contents ->
    let+ files, dirs =
      Fs_memo.Dir_contents.to_list dir_contents
      |> Memo.parallel_map ~f:(fun (fn, (kind : File_kind.t)) ->
        let identity = Path.Source.relative_fname path_for_hint fn in
        let child_physical = Path.Outside_build_dir.relative_fname physical fn in
        if is_special kind || Path.Source.is_in_build_dir identity || is_temp_file fn
        then Memo.return List.Skip
        else
          let+ is_directory, file =
            match kind with
            | S_DIR ->
              let+ file =
                File.of_path child_physical
                >>| function
                | Ok file -> file
                | Error _ -> File.dummy
              in
              true, file
            | S_LNK ->
              Fs_memo.path_stat child_physical
              >>| (function
               | Ok ({ st_kind = S_DIR; _ } as st) -> true, File.of_stats st
               | Ok _ | Error _ -> false, File.dummy)
            | _ -> Memo.return (false, File.dummy)
          in
          if is_directory then List.Right (fn, file) else Left fn)
      >>| List.filter_partition_map ~f:Fun.id
    in
    let dirs = Filename.Array.Map.of_sorted_list_exn dirs in
    { files = Filename.Array.Set.of_sorted_list files; dirs } |> Result.ok
;;

let of_source_path_impl path =
  of_outside_build_dir_impl ~path_for_hint:path ~physical:(In_source_dir path)
;;

(* Having a cutoff here speeds up incremental rebuilds quite a bit when a
   directory contents is invalidated but the result stays the same. *)
let of_source_path_memo =
  Memo.create
    "readdir-of-source-path"
    ~input:(module Path.Source)
    ~cutoff:(Result.equal equal Unix_error.Detailed.equal)
    of_source_path_impl
;;

let of_source_path = Memo.exec of_source_path_memo

let of_outside_build_dir ~path_for_hint ~physical =
  match physical with
  | Path.Outside_build_dir.In_source_dir p when Path.Source.equal p path_for_hint ->
    of_source_path path_for_hint
  | _ -> of_outside_build_dir_impl ~path_for_hint ~physical
;;
