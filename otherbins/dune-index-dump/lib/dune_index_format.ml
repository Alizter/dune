open Stdune

type lid =
  { name : string
  ; loc : Loc.t
  }

type uid_entry =
  { kind : string
  ; comp_unit : string
  ; id : int
  ; locs : lid list
  ; related_group_size : int
  ; impl_id : int option
  }

let sexp_field fields name =
  List.find_map fields ~f:(fun (f : Sexp.t) ->
    match f with
    | List [ Atom n; Atom v ] when String.equal n name -> Some v
    | _ -> None)
;;

let lid_to_sexp { name; loc } =
  let start = Loc.start loc in
  let stop = Loc.stop loc in
  let open Sexp in
  List
    [ List [ Atom "name"; Atom name ]
    ; List [ Atom "file"; Atom start.pos_fname ]
    ; List [ Atom "line"; Atom (string_of_int start.pos_lnum) ]
    ; List [ Atom "start_bol"; Atom (string_of_int start.pos_bol) ]
    ; List [ Atom "start_cnum"; Atom (string_of_int start.pos_cnum) ]
    ; List [ Atom "end_bol"; Atom (string_of_int stop.pos_bol) ]
    ; List [ Atom "end_cnum"; Atom (string_of_int stop.pos_cnum) ]
    ]
;;

let lid_of_sexp (sexp : Sexp.t) =
  match sexp with
  | List fields ->
    let open Option.O in
    let* name = sexp_field fields "name" in
    let* file = sexp_field fields "file" in
    let* line = sexp_field fields "line" |> Option.bind ~f:Int.of_string in
    let* start_bol = sexp_field fields "start_bol" |> Option.bind ~f:Int.of_string in
    let* start_cnum = sexp_field fields "start_cnum" |> Option.bind ~f:Int.of_string in
    let* end_bol = sexp_field fields "end_bol" |> Option.bind ~f:Int.of_string in
    let* end_cnum = sexp_field fields "end_cnum" |> Option.bind ~f:Int.of_string in
    let loc =
      Loc.create
        ~start:
          { Lexing.pos_fname = file
          ; pos_lnum = line
          ; pos_bol = start_bol
          ; pos_cnum = start_cnum
          }
        ~stop:
          { Lexing.pos_fname = file
          ; pos_lnum = line
          ; pos_bol = end_bol
          ; pos_cnum = end_cnum
          }
    in
    Some { name; loc }
  | _ -> None
;;

let uid_entry_to_sexp e =
  let open Sexp in
  List
    ([ List [ Atom "kind"; Atom e.kind ]
     ; List [ Atom "comp_unit"; Atom e.comp_unit ]
     ; List [ Atom "id"; Atom (string_of_int e.id) ]
     ; List (Atom "locs" :: List.map e.locs ~f:lid_to_sexp)
     ; List [ Atom "related_group_size"; Atom (string_of_int e.related_group_size) ]
     ]
     @
     match e.impl_id with
     | Some iid -> [ List [ Atom "impl_id"; Atom (string_of_int iid) ] ]
     | None -> [])
;;

let uid_entry_of_sexp (sexp : Sexp.t) =
  match sexp with
  | List fields ->
    let open Option.O in
    let* kind = sexp_field fields "kind" in
    let* comp_unit = sexp_field fields "comp_unit" in
    let* id = sexp_field fields "id" |> Option.bind ~f:Int.of_string in
    let locs =
      List.find_map fields ~f:(fun (f : Sexp.t) ->
        match f with
        | List (Atom "locs" :: rest) -> Some (List.filter_map rest ~f:lid_of_sexp)
        | _ -> None)
      |> Option.value ~default:[]
    in
    let related_group_size =
      sexp_field fields "related_group_size"
      |> Option.bind ~f:Int.of_string
      |> Option.value ~default:0
    in
    let impl_id = sexp_field fields "impl_id" |> Option.bind ~f:Int.of_string in
    Some { kind; comp_unit; id; locs; related_group_size; impl_id }
  | _ -> None
;;

let to_sexp entries = Sexp.List (List.map entries ~f:uid_entry_to_sexp)

let of_sexp (sexp : Sexp.t) =
  match sexp with
  | List entries -> List.filter_map entries ~f:uid_entry_of_sexp
  | _ -> []
;;

let of_csexp_string s =
  match Csexp.parse_string s with
  | Ok sexp -> of_sexp sexp
  | Error _ ->
    []
;;
