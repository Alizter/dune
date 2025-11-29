open Stdune
module Process = Dune_engine.Process
open Fiber.O

module Format : sig
  type t =
    | Tar
    | Tar_gz
    | Tar_bz2
    | Zip

  val of_filename : Filename.t -> t option
end = struct
  type t =
    | Tar
    | Tar_gz
    | Tar_bz2
    | Zip

  let of_filename =
    let extensions =
      [ ".tar", Tar
      ; ".tar.gz", Tar_gz
      ; ".tgz", Tar_gz
      ; ".tar.bz2", Tar_bz2
      ; ".tbz", Tar_bz2
      ; ".zip", Zip
      ]
    in
    fun filename ->
      let check_suffix suffix = Filename.check_suffix filename suffix in
      List.find_map extensions ~f:(fun (ext, format) ->
        Option.some_if (check_suffix ext) format)
  ;;
end

let is_supported filename = Option.is_some (Format.of_filename filename)
let which bin_name = Bin.which ~path:(Env_path.path Env.initial) bin_name

module Tar : sig
  type t

  val bin_names : string list
  val find : t option Fiber.Lazy.t
  val can_extract_zip : t -> bool
  val path : t -> Path.t
  val args : t -> Format.t -> archive:Path.t -> target:Path.t -> string list
end = struct
  type kind =
    | Bsd
    | Other

  type t =
    { path : Path.t
    ; kind : kind
    }

  let bin_names = [ "tar"; "bsdtar"; "tar.exe" ]

  let detect_kind bin =
    let+ output, _ = Process.run_capture ~display:Quiet Return bin [ "--version" ] in
    let re = Re.compile (Re.alt [ Re.str "bsdtar"; Re.str "libarchive" ]) in
    if Re.execp re output then Bsd else Other
  ;;

  let find =
    Fiber.Lazy.create (fun () ->
      match List.find_map bin_names ~f:which with
      | None -> Fiber.return None
      | Some path ->
        let+ kind = detect_kind path in
        Some { path; kind })
  ;;

  let can_extract_zip t =
    match t.kind with
    | Bsd -> true
    | Other -> false
  ;;

  let path t = t.path

  let args _ format ~archive ~target =
    let decompress_flag =
      match format with
      | Format.Tar | Zip -> []
      | Tar_gz -> [ "-z" ]
      | Tar_bz2 -> [ "-j" ]
    in
    [ "-x" ]
    @ decompress_flag
    @ [ "-f"; Path.to_string archive; "-C"; Path.to_string target ]
  ;;
end

module Unzip : sig
  type t

  val find : t option Fiber.Lazy.t
  val path : t -> Path.t
  val args : t -> archive:Path.t -> target:Path.t -> string list
end = struct
  type t =
    | Unzip of Path.t
    | Tar of Tar.t

  let find =
    Fiber.Lazy.create (fun () ->
      match which "unzip" with
      | Some path -> Fiber.return (Some (Unzip path))
      | None ->
        let+ tar = Fiber.Lazy.force Tar.find in
        (match tar with
         | Some tar when Tar.can_extract_zip tar -> Some (Tar tar)
         | _ -> None))
  ;;

  let path = function
    | Unzip path -> path
    | Tar tar -> Tar.path tar
  ;;

  let args t ~archive ~target =
    match t with
    | Unzip _ -> [ Path.to_string archive; "-d"; Path.to_string target ]
    | Tar _ -> [ "-x"; "-f"; Path.to_string archive; "-C"; Path.to_string target ]
  ;;
end

module Extractor : sig
  type t

  val for_format : Format.t -> archive:Path.t -> target:Path.t -> t Fiber.t
  val run : t -> archive:Path.t -> unit Fiber.t
end = struct
  type t =
    { bin : Path.t
    ; args : string list
    }

  let for_format format ~archive ~target =
    match (format : Format.t) with
    | Tar | Tar_gz | Tar_bz2 ->
      let+ tar = Fiber.Lazy.force Tar.find in
      (match tar with
       | Some tar -> { bin = Tar.path tar; args = Tar.args tar format ~archive ~target }
       | None ->
         User_error.raise
           [ Pp.text "No program found to extract tar files. Tried:"
           ; Pp.enumerate Tar.bin_names ~f:Pp.verbatim
           ])
    | Zip ->
      let+ unzip = Fiber.Lazy.force Unzip.find in
      (match unzip with
       | Some unzip ->
         { bin = Unzip.path unzip; args = Unzip.args unzip ~archive ~target }
       | None ->
         User_error.raise
           [ Pp.text "No program found to extract zip file. Tried:"
           ; Pp.enumerate ("unzip" :: Tar.bin_names) ~f:Pp.verbatim
           ])
  ;;

  let output_limit = 1_000_000

  let run { bin; args } ~archive =
    let prefix = "extract" in
    let temp_stderr = Temp.create File ~prefix ~suffix:"stderr" in
    Fiber.finalize ~finally:(fun () ->
      Temp.destroy File temp_stderr;
      Fiber.return ())
    @@ fun () ->
    let stdout_to = Process.Io.make_stdout ~output_on_success:Swallow ~output_limit in
    let stderr_to = Process.Io.file temp_stderr Out in
    let+ (), exit_code =
      Process.run ~display:Quiet ~stdout_to ~stderr_to Return bin args
    in
    if exit_code <> 0
    then
      Io.with_file_in temp_stderr ~f:(fun err_channel ->
        let stderr_lines = Io.input_lines err_channel in
        User_error.raise
          [ Pp.textf "failed to extract '%s'" (Path.basename archive)
          ; Pp.concat
              ~sep:Pp.space
              [ Pp.text "Reason:"
              ; User_message.command @@ Path.basename bin
              ; Pp.textf "failed with non-zero exit code '%d' and output:" exit_code
              ]
          ; Pp.enumerate stderr_lines ~f:Pp.text
          ])
  ;;
end

let extract ~archive ~target =
  let format =
    Format.of_filename (Path.to_string archive) |> Option.value ~default:Format.Tar
  in
  let target_in_temp =
    let prefix = Path.basename target in
    let suffix = Path.basename archive in
    Temp_dir.dir_for_target ~target ~prefix ~suffix
  in
  Fiber.finalize ~finally:(fun () ->
    Temp.destroy Dir target_in_temp;
    Fiber.return ())
  @@ fun () ->
  Path.mkdir_p target_in_temp;
  let* extractor = Extractor.for_format format ~archive ~target:target_in_temp in
  let+ () = Extractor.run extractor ~archive in
  let target_in_temp =
    match Path.readdir_unsorted_with_kinds target_in_temp with
    | Error e ->
      User_error.raise
        [ Pp.textf "failed to extract %s" (Path.to_string_maybe_quoted archive)
        ; Pp.text "reason:"
        ; Pp.text (Unix_error.Detailed.to_string_hum e)
        ]
    | Ok [ (fname, S_DIR) ] -> Path.relative target_in_temp fname
    | Ok _ -> target_in_temp
  in
  Path.mkdir_p (Path.parent_exn target);
  Path.rename target_in_temp target;
  Ok ()
;;
