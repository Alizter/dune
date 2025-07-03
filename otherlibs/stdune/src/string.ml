(* Because other the syntax s.[x] causes trouble *)
module String = Stdlib.String

module StringLabels = struct
  (* functions potentially in the stdlib, depending on OCaml version *)

  let[@warning "-32"] exists =
    let rec loop s i len f =
      if i = len then false else f (String.unsafe_get s i) || loop s (i + 1) len f
    in
    fun ~f s -> loop s 0 (String.length s) f
  ;;

  let[@warning "-32"] for_all =
    let rec loop s i len f =
      i = len || (f (String.unsafe_get s i) && loop s (i + 1) len f)
    in
    fun ~f s -> loop s 0 (String.length s) f
  ;;

  (* overwrite them with stdlib versions if available *)
  include Stdlib.StringLabels
end

include StringLabels

let compare a b = Ordering.of_int (String.compare a b)

module T = struct
  type t = StringLabels.t

  let compare = compare
  let equal (x : t) (y : t) = x = y
  let hash (s : t) = Poly.hash s
  let to_dyn s = Dyn.String s
end

let to_dyn = T.to_dyn
let equal : string -> string -> bool = ( = )
let hash = Poly.hash
let capitalize = capitalize_ascii
let uncapitalize = uncapitalize_ascii
let uppercase = uppercase_ascii
let lowercase = lowercase_ascii
let index = index_opt
let index_from = index_from_opt
let rindex = rindex_opt
let rindex_from = rindex_from_opt
let break s ~pos = sub s ~pos:0 ~len:pos, sub s ~pos ~len:(length s - pos)
let is_empty s = length s = 0

module Cased_functions (X : sig
    val normalize : char -> char
  end) =
struct
  let rec check_prefix s ~prefix len i =
    i = len
    || (X.normalize s.[i] = X.normalize prefix.[i] && check_prefix s ~prefix len (i + 1))
  ;;

  let rec check_suffix s ~suffix suffix_len offset i =
    i = suffix_len
    || (X.normalize s.[offset + i] = X.normalize suffix.[i]
        && check_suffix s ~suffix suffix_len offset (i + 1))
  ;;

  let is_prefix s ~prefix =
    let len = length s in
    let prefix_len = length prefix in
    len >= prefix_len && check_prefix s ~prefix prefix_len 0
  ;;

  let is_suffix s ~suffix =
    let len = length s in
    let suffix_len = length suffix in
    len >= suffix_len && check_suffix s ~suffix suffix_len (len - suffix_len) 0
  ;;

  let drop_prefix s ~prefix =
    if is_prefix s ~prefix
    then
      if length s = length prefix
      then Some ""
      else Some (sub s ~pos:(length prefix) ~len:(length s - length prefix))
    else None
  ;;

  let drop_prefix_if_exists s ~prefix =
    match drop_prefix s ~prefix with
    | None -> s
    | Some s -> s
  ;;

  let drop_suffix s ~suffix =
    if is_suffix s ~suffix
    then
      if length s = length suffix
      then Some ""
      else Some (sub s ~pos:0 ~len:(length s - length suffix))
    else None
  ;;

  let drop_suffix_if_exists s ~suffix =
    match drop_suffix s ~suffix with
    | None -> s
    | Some s -> s
  ;;
end

include Cased_functions (struct
    let normalize c = c
  end)

module Caseless = Cased_functions (struct
    let normalize = Char.lowercase_ascii
  end)

let extract_words s ~is_word_char =
  let rec skip_blanks i =
    if i = length s
    then []
    else if is_word_char s.[i]
    then parse_word i (i + 1)
    else skip_blanks (i + 1)
  and parse_word i j =
    if j = length s
    then [ sub s ~pos:i ~len:(j - i) ]
    else if is_word_char s.[j]
    then parse_word i (j + 1)
    else sub s ~pos:i ~len:(j - i) :: skip_blanks (j + 1)
  in
  skip_blanks 0
;;

let extract_comma_space_separated_words s =
  extract_words s ~is_word_char:(function
    | ',' | ' ' | '\t' | '\n' -> false
    | _ -> true)
;;

let extract_blank_separated_words s =
  extract_words s ~is_word_char:(function
    | ' ' | '\t' -> false
    | _ -> true)
;;

let lsplit2 s ~on =
  match index s on with
  | None -> None
  | Some i -> Some (sub s ~pos:0 ~len:i, sub s ~pos:(i + 1) ~len:(length s - i - 1))
;;

let lsplit2_exn s ~on =
  match lsplit2 s ~on with
  | Some s -> s
  | None -> Code_error.raise "lsplit2_exn" [ "s", String s; "on", Char on ]
;;

let rsplit2 s ~on =
  match rindex s on with
  | None -> None
  | Some i -> Some (sub s ~pos:0 ~len:i, sub s ~pos:(i + 1) ~len:(length s - i - 1))
;;

include String_split

let escape_only c s =
  let n = ref 0 in
  let len = length s in
  for i = 0 to len - 1 do
    if unsafe_get s i = c then incr n
  done;
  if !n = 0
  then s
  else (
    let b = Bytes.create (len + !n) in
    n := 0;
    for i = 0 to len - 1 do
      if unsafe_get s i = c
      then (
        Bytes.unsafe_set b !n '\\';
        incr n);
      Bytes.unsafe_set b !n (unsafe_get s i);
      incr n
    done;
    Bytes.unsafe_to_string b)
;;

let longest_map l ~f = List.fold_left l ~init:0 ~f:(fun acc x -> max acc (length (f x)))
let longest l = longest_map l ~f:Fun.id

let longest_prefix = function
  | [] -> ""
  | [ x ] -> x
  | x :: xs ->
    let rec loop len i =
      if i < len && List.for_all xs ~f:(fun s -> s.[i] = x.[i])
      then loop len (i + 1)
      else i
    in
    let len = List.fold_left ~init:(length x) ~f:(fun acc x -> min acc (length x)) xs in
    sub ~pos:0 x ~len:(loop len 0)
;;

let quoted = Printf.sprintf "%S"

let maybe_quoted s =
  let escaped = escaped s in
  if (s == escaped || s = escaped) && not (String.contains s ' ') then s else quoted s
;;

include Comparable.Make (T)
module Table = Hashtbl.Make (T)

let enumerate_gen s =
  let s = " " ^ s ^ " " in
  let rec loop = function
    | [] -> []
    | [ x ] -> [ x ]
    | [ x; y ] -> [ x; s; y ]
    | x :: l -> x :: ", " :: loop l
  in
  fun l -> concat (loop l) ~sep:""
;;

let enumerate_and = enumerate_gen "and"
let enumerate_or = enumerate_gen "or"

let enumerate_one_of = function
  | [ x ] -> x
  | s -> "One of " ^ enumerate_or s
;;

let take s len = sub s ~pos:0 ~len:(min (length s) len)

let drop s n =
  let len = length s in
  sub s ~pos:(min n len) ~len:(max (len - n) 0)
;;

let split_n s n =
  let len = length s in
  let n = min n len in
  sub s ~pos:0 ~len:n, sub s ~pos:n ~len:(len - n)
;;

let findi =
  let rec loop s len ~f i =
    if i >= len
    then None
    else if f (String.unsafe_get s i)
    then Some i
    else loop s len ~f (i + 1)
  in
  fun s ~f -> loop s (String.length s) ~f 0
;;

let rfindi =
  let rec loop s ~f i =
    if i < 0 then None else if f (String.unsafe_get s i) then Some i else loop s ~f (i - 1)
  in
  fun s ~f -> loop s ~f (String.length s - 1)
;;

let need_quoting s =
  let len = String.length s in
  len = 0
  ||
  let rec loop i =
    if i = len
    then false
    else (
      match s.[i] with
      | ' ' | '\"' | '(' | ')' | '{' | '}' | ';' | '#' -> true
      | _ -> loop (i + 1))
  in
  loop 0
;;

let quote_for_shell s = if need_quoting s then Stdlib.Filename.quote s else s

let quote_list_for_shell = function
  | [] -> ""
  | prog :: args ->
    let prog =
      if Sys.win32 && contains prog '/'
      then
        map
          ~f:(function
            | '/' -> '\\'
            | c -> c)
          prog
      else prog
    in
    quote_for_shell prog :: List.map ~f:quote_for_shell args |> concat ~sep:" "
;;

let of_list chars =
  let s = Bytes.make (List.length chars) '0' in
  List.iteri chars ~f:(fun i c -> Bytes.set s i c);
  Bytes.to_string s
;;

let filter_map t ~f =
  (* TODO more efficient implementation *)
  to_seq t |> Seq.filter_map ~f |> of_seq
;;

let drop_prefix_and_suffix t ~prefix ~suffix =
  let p_len = String.length prefix in
  let s_len = String.length suffix in
  let t_len = String.length t in
  let p_s_len = p_len + s_len in
  if p_s_len <= t_len && is_prefix t ~prefix && is_suffix t ~suffix
  then Some (sub t ~pos:p_len ~len:(t_len - p_s_len))
  else None
;;

let contains_double_underscore =
  let rec aux s len i =
    if i > len - 2
    then false
    else if s.[i] = '_' && s.[i + 1] = '_'
    then true
    else aux s len (i + 1)
  in
  fun s -> aux s (String.length s) 0
;;

let last s = if length s > 0 then Some s.[length s - 1] else None

let replace_char s ~from ~to_ =
  String.map (fun c -> if Char.equal c from then to_ else c) s
;;

(* Spellchecking *)

module Uchar = Stdlib.Uchar

let uchar_array_of_utf_8_string s =
  let slen = length s in
  (* is an upper bound on Uchar.t count *)
  let uchars = Array.make slen Uchar.max in
  let k = ref 0
  and i = ref 0 in
  while !i < slen do
    let dec = get_utf_8_uchar s !i in
    i := !i + Uchar.utf_decode_length dec;
    uchars.(!k) <- Uchar.utf_decode_uchar dec;
    incr k
  done;
  uchars, !k
;;

let edit_distance' ?(limit = Int.max_int) s (s0, len0) s1 =
  if limit <= 1
  then if equal s s1 then 0 else limit
  else (
    let[@inline] minimum a b c = Int.min a (Int.min b c) in
    let s1, len1 = uchar_array_of_utf_8_string s1 in
    let limit = Int.min (Int.max len0 len1) limit in
    if Int.abs (len1 - len0) >= limit
    then limit
    else (
      let s0, s1 = if len0 > len1 then s0, s1 else s1, s0 in
      let len0, len1 = if len0 > len1 then len0, len1 else len1, len0 in
      let rec loop row_minus2 row_minus1 row i len0 limit s0 s1 =
        if i > len0
        then row_minus1.(Array.length row_minus1 - 1)
        else (
          let len1 = Array.length row - 1 in
          let row_min = ref Int.max_int in
          row.(0) <- i;
          let jmax =
            let jmax = Int.min len1 (i + limit - 1) in
            if jmax < 0 then (* overflow *) len1 else jmax
          in
          for j = Int.max 1 (i - limit) to jmax do
            let cost = if Uchar.equal s0.(i - 1) s1.(j - 1) then 0 else 1 in
            let min =
              minimum
                (row_minus1.(j - 1) + cost) (* substitute *)
                (row_minus1.(j) + 1) (* delete *)
                (row.(j - 1) + 1)
              (* insert *)
              (* Note when j = i - limit, the latter [row] read makes a bogus read
             on the value that was in the matrix at d.(i-2).(i - limit - 1).
             Since by induction for all i,j, d.(i).(j) >= abs (i - j),
             (row.(j-1) + 1) is greater or equal to [limit] and thus does
             not affect adversely the minimum computation. *)
            in
            let min =
              if
                i > 1
                && j > 1
                && Uchar.equal s0.(i - 1) s1.(j - 2)
                && Uchar.equal s0.(i - 2) s1.(j - 1)
              then Int.min min (row_minus2.(j - 2) + cost) (* transpose *)
              else min
            in
            row.(j) <- min;
            row_min := Int.min !row_min min
          done;
          if !row_min >= limit
          then (* can no longer decrease *) limit
          else loop row_minus1 row row_minus2 (i + 1) len0 limit s0 s1)
      in
      let ignore =
        (* Value used to make the values around the diagonal stripe ignored
       by the min computations when we have a limit. *)
        limit + 1
      in
      let row_minus2 = Array.make (len1 + 1) ignore in
      let row_minus1 = Array.init (len1 + 1) ~f:Fun.id in
      let row = Array.make (len1 + 1) ignore in
      let d = loop row_minus2 row_minus1 row 1 len0 limit s0 s1 in
      if d > limit then limit else d))
;;

let edit_distance ~limit s0 s1 =
  let us0 = uchar_array_of_utf_8_string s0 in
  edit_distance' ~limit s0 us0 s1
;;
