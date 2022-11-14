open Import
module Path = Coq_module.Path
module Name = Coq_module.Name

let _debug = false

type 'a node =
  | Leaf of 'a
  | Tree of 'a node Name.Map.t
  | Tree' of 'a * 'a node Name.Map.t

(* a.v a/b.v *)

type 'a t = 'a node Name.Map.t

let rec union x y =
  Name.Map.union x y ~f:(fun _ x y ->
      match (x, y) with
      | (Leaf _ | Tree' _), (Leaf _ | Tree' _) ->
        User_error.raise [ Pp.textf "TODO conflict" ]
      | Leaf l, Tree t | Tree t, Leaf l -> Some (Tree' (l, t))
      | Tree t, Tree' (l, t') | Tree' (l, t'), Tree t ->
        Some (Tree' (l, union t t'))
      | Tree t', Tree t -> Some (Tree (union t t')))

(* Invariant Leaf and Tree are mutually exclusive the combination of both is
   Tree' *)

let empty = Name.Map.empty

let singleton (type a) path (x : a) : a node =
  List.fold_right path ~init:(Leaf x) ~f:(fun a acc ->
      Tree (Name.Map.singleton a acc))

let rec add : 'a. 'a t -> Name.t list -> 'a -> 'a t =
 fun t path x ->
  match path with
  | [] -> assert false
  | [ p ] -> (
    match Name.Map.find t p with
    | None -> Name.Map.set t p (Leaf x)
    | Some (Tree y) -> Name.Map.set t p (Tree' (x, y))
    | Some (Leaf _) | Some (Tree' (_, _)) -> failwith "override")
  | p :: (_ :: _ as ps) -> (
    match Name.Map.find t p with
    | None -> Name.Map.add_exn t p (singleton ps x)
    | Some (Leaf x) ->
      let v = Tree' (x, t) in
      Name.Map.set t p v
    | Some (Tree m) ->
      let v = add m ps x in
      Name.Map.set t p (Tree v)
    | Some (Tree' (y, m)) ->
      let v = Tree' (y, add m ps x) in
      Name.Map.set t p v)

let add t path a = add t (Path.to_list path) a

let of_modules ~skip_theory_prefix modules =
  List.fold_left modules ~init:empty ~f:(fun acc m ->
      let path = Path.rev (Coq_module.path ~skip_theory_prefix m) in
      if _debug then
        Printf.printf "adding %s to require map\n"
          (Path.to_dyn path |> Dyn.to_string);

      add acc path m)

let rec fold t ~init ~f =
  Name.Map.fold t ~init ~f:(fun a init ->
      match a with
      | Leaf a -> f a init
      | Tree' (x, ts) ->
        let init = f x init in
        fold ts ~init ~f
      | Tree t -> fold t ~init ~f)

let rec dyn_of_node node : Dyn.t =
  match node with
  | Leaf x -> Dyn.variant "Leaf" [ Coq_module.to_dyn x ]
  | Tree m -> Dyn.variant "Tree" [ Name.Map.to_dyn dyn_of_node m ]
  | Tree' (x, m) ->
    Dyn.variant "Tree'"
      [ Tuple [ Coq_module.to_dyn x; Name.Map.to_dyn dyn_of_node m ] ]

let to_dyn t : Dyn.t = Name.Map.to_dyn dyn_of_node t

let find_all t ~prefix ~suffix =
  if _debug then
    Printf.printf "  Coq_require_map.find_all ~prefix:%s ~suffix:%s\n"
      (Path.to_dyn prefix |> Dyn.to_string)
      (Path.to_dyn suffix |> Dyn.to_string);
  let prefix = Path.to_list prefix in
  let suffix = Path.to_list suffix in
  if _debug then
    Printf.printf "  - prefix:%s suffix:%s\n"
      (Dyn.list Name.to_dyn prefix |> Dyn.to_string)
      (Dyn.list Name.to_dyn suffix |> Dyn.to_string);
  let rec check_prefix m m_prefix prefix =
    if _debug then
      Printf.printf "  check_prefix %s %s %s\n"
        (Coq_module.to_dyn m |> Dyn.to_string)
        (Dyn.list Name.to_dyn m_prefix |> Dyn.to_string)
        (Dyn.list Name.to_dyn prefix |> Dyn.to_string);
    match (m_prefix, prefix) with
    | _, [] -> true
    | [], [ x ] -> Coq_module.Name.equal x (Coq_module.name m)
    | x :: m_prefix, y :: prefix ->
      Coq_module.Name.equal x y && check_prefix m m_prefix prefix
    | _, _ -> false
  in
  let add acc m =
    if check_prefix m (Path.to_list (Coq_module.path m)) prefix then (
      if _debug then Printf.printf "  check_prefix = true\n";
      m :: acc)
    else (
      if _debug then Printf.printf "  check_prefix = false\n";
      acc)
  in
  let rec loop acc (t : Coq_module.t t) path =
    if _debug then
      Printf.printf "  loop acc:%s t:%s path%s\n"
        (Dyn.list Coq_module.to_dyn acc |> Dyn.to_string)
        (* (to_dyn t |> Dyn.to_string) *)
        "some map"
        (Dyn.list Name.to_dyn path |> Dyn.to_string);
    match path with
    | [] ->
      if _debug then Printf.printf "  - fold\n";
      fold t ~init:acc ~f:(fun x y -> add y x)
    | p :: ps -> (
      if _debug then
        Printf.printf "  - find p:%s\n" (Name.to_dyn p |> Dyn.to_string);

      match Name.Map.find t p with
      | None ->
        if _debug then Printf.printf "    - None\n";
        acc
      | Some (Leaf s) -> (
        if _debug then
          Printf.printf "    - Some Leaf s:%s\n"
            (Coq_module.to_dyn s |> Dyn.to_string);
        match ps with
        | [] -> add acc s
        | _ :: _ -> acc)
      | Some (Tree t) ->
        if _debug then Printf.printf "    - Some Tree\n";
        loop acc t ps
      | Some (Tree' (s, t)) ->
        if _debug then Printf.printf "    - Tree'\n";
        let acc =
          match ps with
          | [] -> add acc s
          | _ :: _ -> acc
        in
        loop acc t ps)
  in
  loop [] t (List.rev suffix)
  (* get rid of duplicates *)
  |> List.fold_right ~init:[] ~f:(fun m ms ->
         if List.mem ms m ~equal:Coq_module.equal then ms else m :: ms)

let rec t_equal ~equal t1 t2 = Name.Map.equal ~equal:(node_equal ~equal) t1 t2

and node_equal ~equal x y =
  match (x, y) with
  | Leaf x, Leaf y -> equal x y
  | Tree m, Tree n -> t_equal ~equal m n
  | Tree' (x, m), Tree' (y, n) -> equal x y && t_equal ~equal m n
  | _, _ -> false

let equal t1 t2 = t_equal ~equal:Coq_module.equal t1 t2

let merge_all = function
  | [] -> empty
  | init :: xs -> List.fold_left ~init ~f:union xs
