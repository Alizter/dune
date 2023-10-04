type (_, _) t =
  | [] : ('finish, 'finish) t
  | ( :: ) : 'start * ('mid, 'finish) t -> ('start -> 'mid, 'finish) t

let rec ( @ )
  : type start mid finish. (start, mid) t -> (mid, finish) t -> (start, finish) t
  =
  fun l r ->
  match l with
  | [] -> r
  | h :: t -> h :: (t @ r)
;;

module type TypeComparison = sig
  type t
end

let split_exn : type a b c. (a -> b, c) t -> a * (b, c) t = function
  | hd :: tl -> hd, tl
  | _ ->
    let module A = struct
      type t = a -> b
    end
    in
    let module B = struct
      type t = c
    end
    in
    if (module A : TypeComparison) != (module B : TypeComparison)
    then Code_error.raise "split_exn: impossible" []
    else Code_error.raise "split_exn: splitting empty list" []
;;

let split : type a b c. (a -> b, c) t -> (a * (b, c) t) option = function
  | hd :: tl -> Some (hd, tl)
  | _ -> None
;;

let singleton x = x :: []
let of_pair (a, b) = [ a; b ]
let of_triple (a, b, c) = [ a; b; c ]
let hd t = fst (split_exn t)
let tl t = snd (split_exn t)

let to_pair : type a b c. (a -> b -> c, c) t -> a * b = function
  | [ a; b ] -> a, b
  | _ -> Code_error.raise "to_pair: not a pair" []
;;

let to_triple : type a b c d. (a -> b -> c -> d, d) t -> a * b * c = function
  | [ a; b; c ] -> a, b, c
  | _ -> Code_error.raise "to_triple: not a triple" []
;;

(* let to_dyn arg_to_dyns t =
   let rec loop : type a b.  -> _ -> Dyn.t list =
   fun arg_to_dyns t ->
   let arg_to_dyn, other_to_dyns = split_exn arg_to_dyns in
   let hd, tl = split_exn t in
   arg_to_dyn hd :: loop other_to_dyns tl
   in
   Dyn.list Fun.id (loop arg_to_dyns t)
   ;; *)

let inner_empty_to_dyn _ _ : Dyn.t list = []
let empty_to_dyn x t = inner_empty_to_dyn x t |> Dyn.list Fun.id

let inner_singleton_to_dyn to_dyn t : Dyn.t list =
  let to_dyn, other_to_dyn = split_exn to_dyn in
  let hd, tl = split_exn t in
  to_dyn hd :: inner_empty_to_dyn other_to_dyn tl
;;

let singleton_to_dyn to_dyn t = inner_singleton_to_dyn to_dyn t |> Dyn.list Fun.id

let inner_pair_to_dyn to_dyn t : Dyn.t list =
  let to_dyn, other_to_dyn = split_exn to_dyn in
  let hd, tl = split_exn t in
  to_dyn hd :: inner_singleton_to_dyn other_to_dyn tl
;;

let pair_to_dyn to_dyn t = inner_pair_to_dyn to_dyn t |> Dyn.list Fun.id

let rec inner : type a b c d e. ((a -> Dyn.t) -> b, c) t -> (a -> d, e) t -> Dyn.t list =
  fun to_dyn t ->
  match t, to_dyn with
  | hd :: tl, to_dyn :: other_to_dyns ->
    to_dyn hd :: inner (Obj.magic other_to_dyns) (Obj.magic tl)
  | _, _ -> inner_empty_to_dyn to_dyn t
;;

let to_dyn to_dyn t = inner to_dyn t |> Dyn.list Fun.id

let rec apply : type a b c d. ((a -> b) -> c, d) t -> (a, d) t -> (b, d) t =
  fun f t ->
  match f, t with
  | hd_f :: tl_f, hd_t :: tl_t ->
    Obj.magic (hd_f (Obj.magic hd_t) :: apply (Obj.magic tl_f) (Obj.magic tl_t))
  | [], _ -> Obj.magic []
  | _, [] -> Obj.magic []
  | [], [] -> .
;;
