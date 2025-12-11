open Import

type key =
  { source_digest : Digest.t
  ; ocaml_digest : Digest.t
  ; flags_digest : Digest.t
  }

type value =
  { imported_intf : Module_name.Unique.Set.t
  ; imported_impl : Module_name.Unique.Set.t
  }

(* Compute an action digest from the key to use with the Value storage API *)
let action_digest_of_key { source_digest; ocaml_digest; flags_digest } =
  (* Use a version prefix to allow future changes to the storage format *)
  Digest.generic ("fine-grained-deps-v1", source_digest, ocaml_digest, flags_digest)
;;

(* Serialize a Module_name.Unique.Set.t to a list of strings *)
let set_to_sexp set =
  Module_name.Unique.Set.to_list set
  |> List.map ~f:(fun m -> Sexp.Atom (Module_name.Unique.to_string m))
  |> fun l -> Sexp.List l
;;

(* Deserialize a Module_name.Unique.Set.t from a sexp *)
let set_of_sexp sexp =
  match (sexp : Sexp.t) with
  | List atoms ->
    List.map atoms ~f:(function
      | Sexp.Atom s -> Module_name.Unique.of_string s
      | Sexp.List _ -> failwith "Expected atom in module name set")
    |> Module_name.Unique.Set.of_list
  | Sexp.Atom _ -> failwith "Expected list for module name set"
;;

(* Serialize value to string for storage *)
let value_to_string { imported_intf; imported_impl } =
  let sexp =
    Sexp.List
      [ List [ Atom "intf"; set_to_sexp imported_intf ]
      ; List [ Atom "impl"; set_to_sexp imported_impl ]
      ]
  in
  Csexp.to_string sexp
;;

(* Deserialize value from string *)
let value_of_string s =
  match Csexp.parse_string s with
  | Error (_, msg) -> Error (Failure msg)
  | Ok sexp ->
    (match (sexp : Sexp.t) with
     | List [ List [ Atom "intf"; intf_sexp ]; List [ Atom "impl"; impl_sexp ] ] ->
       (try
          Ok
            { imported_intf = set_of_sexp intf_sexp
            ; imported_impl = set_of_sexp impl_sexp
            }
        with
        | Failure msg -> Error (Failure msg))
     | _ -> Error (Failure "Invalid fine-grained deps format"))
;;

let store ~mode ~key ~value =
  let action_digest = action_digest_of_key key in
  let content = value_to_string value in
  Dune_cache_storage.Value.store ~mode ~action_digest content
;;

let restore ~key =
  let action_digest = action_digest_of_key key in
  match Dune_cache_storage.Value.restore ~action_digest with
  | Restored content ->
    (match value_of_string content with
     | Ok value -> Dune_cache_storage.Restore_result.Restored value
     | Error e -> Error e)
  | Not_found_in_cache -> Not_found_in_cache
  | Error e -> Error e
;;
