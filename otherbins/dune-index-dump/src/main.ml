open Stdune
module IF = Merlin_index_format.Index_format
module Uid = Ocaml_typing.Shape.Uid
module Mloc = Ocaml_parsing.Location
module Lid = Ocaml_parsing.Longident
module F = Dune_index_format

(* Assert that our types coincide with the shared library's types *)
let _ : F.lid -> F.lid = Fun.id
let _ : F.uid_entry -> F.uid_entry = Fun.id

let merlin_loc_to_loc (mloc : Mloc.t) : Loc.t =
  Loc.create ~start:mloc.loc_start ~stop:mloc.loc_end
;;

(** Extract a uid_entry from the index *)
let extract_uid_entry uid locs index : F.uid_entry option =
  match (uid : Uid.t) with
  | Item { comp_unit; from; id } ->
    let kind =
      match from with
      | Intf -> "intf"
      | Impl -> "impl"
    in
    let lids = IF.Lid_set.elements locs |> List.map ~f:IF.Lid.to_lid in
    let locs =
      List.map lids ~f:(fun (lid : Lid.t Mloc.loc) ->
        let name =
          match Lid.flatten lid.txt with
          | s -> String.concat ~sep:"." s
          | exception _ -> "<?>"
        in
        ({ F.name; loc = merlin_loc_to_loc lid.Mloc.loc } : F.lid))
    in
    let related_group_size, impl_id =
      match from with
      | Intf ->
        let group =
          match IF.Uid_map.find_opt uid index.IF.related_uids with
          | Some uf -> IF.Union_find.get uf |> IF.Uid_set.elements
          | None -> []
        in
        let impl_id =
          List.find_map group ~f:(fun (u : Uid.t) ->
            match u with
            | Item { from = Impl; id; _ } -> Some id
            | _ -> None)
        in
        List.length group, impl_id
      | Impl -> 0, None
    in
    Some { F.kind; comp_unit; id; locs; related_group_size; impl_id }
  | Compilation_unit _ | Internal | Predef _ -> None
;;

let extract_all index =
  IF.Uid_map.fold
    (fun uid locs acc ->
       match extract_uid_entry uid locs index with
       | Some entry -> entry :: acc
       | None -> acc)
    index.IF.defs
    []
;;

let () =
  let index_file = ref "" in
  let sexp_mode = ref false in
  let decode_mode = ref false in
  let usage_msg = "dune-index-dump [--sexp] [--decode] <index-file>" in
  let speclist =
    [ "--sexp", Arg.Set sexp_mode, "Output human-readable s-expressions"
    ; ( "--decode"
      , Arg.Set decode_mode
      , "Read csexp from stdin, re-encode to sexp (for round-trip testing)" )
    ]
  in
  Arg.parse speclist (fun f -> index_file := f) usage_msg;
  if !decode_mode
  then (
    let input = In_channel.input_all In_channel.stdin in
    let entries = F.of_csexp_string input in
    Format.printf "%a@." Pp.to_fmt (Sexp.pp (F.to_sexp entries)))
  else (
    if String.equal !index_file ""
    then (
      Printf.eprintf "Error: no index file specified\n";
      exit 2);
    let index = IF.read_exn ~file:!index_file in
    let entries = extract_all index in
    let sexp = F.to_sexp entries in
    if !sexp_mode
    then Format.printf "%a@." Pp.to_fmt (Sexp.pp sexp)
    else Csexp.to_channel stdout sexp)
;;
