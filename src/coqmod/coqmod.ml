open! Stdune

let debug_mode = ref true

let cannot_open s msg =
  User_error.raise Pp.[ Pp.O.(text s ++ text ":" ++ space ++ text msg) ]

let unknwon_output_format format =
  User_error.raise Pp.[ textf "Unkown output format: %s " format ]

let no_file_provided () =
  User_error.raise Pp.[ text "No file provided. Please provide a file." ]

let too_many_files_provided () =
  User_error.raise
    Pp.[ text "Too many files\n  provided. Please provide only a single file." ]

let rec read_buffer t buf =
  match Lexer.parse_coq t buf with
  | t -> read_buffer t buf
  | exception Lexer.End_of_file -> t

let find_dependencies ~format f =
  let print =
    match !format with
    | "csexp" -> fun tok -> Token.to_sexp tok |> Csexp.to_channel stdout
    | "read" -> fun tok -> Printf.printf "%s\n" (Token.to_string tok)
    | "sexp" ->
      fun tok -> Pp.to_fmt Format.std_formatter (Sexp.pp (Token.to_sexp tok))
    | f -> unknwon_output_format f
  in
  let chan = try open_in f with Sys_error msg -> cannot_open f msg in
  let buf = Lexing.from_channel chan in
  let t = Lexing.set_filename buf f; Token.set_filename (Token.empty) f in
  let toks = read_buffer t buf in
  close_in chan;
  print (Token.sort_uniq toks)

let main () =
  let usage_msg = "coqmod - A simple module lexer for Coq" in
  let format = ref "csexp" in
  let files = ref [] in
  let anon_fun f = files := f :: !files in
  let speclist =
    [ ("--format", Arg.Set_string format, "Set output format [csexp|sexp|read]")
    ; ("--debug", Arg.Set debug_mode, "Output debugging information")
    ]
  in
  let () = Arg.parse speclist anon_fun usage_msg in
  match !files with
  | [] -> no_file_provided ()
  | [ file ] -> find_dependencies ~format file
  | _ -> too_many_files_provided ()

let () =
  try main ()
  with exn -> (
    match exn with
    | User_error.E err -> Console.print_user_message err
    | _ -> raise exn)
