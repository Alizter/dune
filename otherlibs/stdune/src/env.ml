module Sys = Stdlib.Sys

module Var = struct
  module T = struct
    type t = string

    let compare =
      if Sys.win32
      then fun a b -> String.compare (String.lowercase a) (String.lowercase b)
      else String.compare
    ;;

    let hash =
      if Sys.win32 then fun var -> String.hash (String.lowercase var) else String.hash
    ;;

    let to_dyn = Dyn.string
  end

  include Comparable.Make (T)
  include T

  let of_string s =
    if String.contains s '\000'
    then
      Code_error.raise
        "Env.Var.of_string: NUL byte in environment variable name"
        [ "name", Dyn.string s ];
    s
  ;;

  let to_string t = t
  let repr = Repr.view Repr.string ~to_:to_string
  let temp_dir = of_string (if Sys.win32 then "TEMP" else "TMPDIR")
  let _PATH = of_string "PATH"
  let _OCAMLPARAM = of_string "OCAMLPARAM"
  let _OCAMLFIND_CONF = of_string "OCAMLFIND_CONF"
  let _INSIDE_EMACS = of_string "INSIDE_EMACS"
  let _LC_ALL = of_string "LC_ALL"
  let _GIT_DIR = of_string "GIT_DIR"
  let _XDG_CACHE_HOME = of_string "XDG_CACHE_HOME"
  let _DUNE_ACTION_TRACE_DIR = of_string "DUNE_ACTION_TRACE_DIR"
end

module Set = Var.Set
module Map = Var.Map

module Value : sig
  type t

  val of_string : string -> t
  val to_string : t -> string
end = struct
  type t = string

  let of_string value =
    if String.contains value '\000'
    then
      Code_error.raise
        "Env: NUL byte in environment variable value"
        [ "value", Dyn.string value ];
    value
  ;;

  let to_string t = t
end

type t =
  { vars : Value.t Map.t
  ; managed_dirs : (char * Path0.Build.Set.t) Map.t
  }

let equal { vars; managed_dirs } t =
  Map.equal
    ~equal:(fun x y -> String.equal (Value.to_string x) (Value.to_string y))
    vars
    t.vars
  && Map.equal
       ~equal:(fun (sep, dirs) (other_sep, other_dirs) ->
         Char.equal sep other_sep && Path0.Build.Set.equal dirs other_dirs)
       managed_dirs
       t.managed_dirs
;;

let hash { vars; managed_dirs } =
  let init =
    Map.foldi vars ~init:(Hash.create ()) ~f:(fun var value acc ->
      let acc = Hash.feed acc (Var.hash var) in
      Hash.feed acc (String.hash (Value.to_string value)))
  in
  Map.foldi managed_dirs ~init ~f:(fun var (sep, dirs) acc ->
    let acc = Hash.feed acc (Var.hash var) in
    let acc = Hash.feed acc (Char.code sep) in
    Path0.Build.Set.fold
      dirs
      ~init:(Hash.feed acc (Path0.Build.Set.cardinal dirs))
      ~f:(fun path acc -> Hash.feed acc (Path0.Build.hash path)))
  |> Hash.hash
;;

let of_map vars = { vars = Map.map vars ~f:Value.of_string; managed_dirs = Map.empty }
let empty = of_map Map.empty
let is_empty { vars; managed_dirs } = Map.is_empty vars && Map.is_empty managed_dirs
let vars { vars; _ } = Set.of_keys vars
let get { vars; _ } var = Option.map (Map.find vars var) ~f:Value.to_string

let managed_dirs { managed_dirs; _ } =
  Map.to_list_map managed_dirs ~f:(fun var (sep, dirs) ->
    var, sep, Path0.Build.Set.to_list dirs)
;;

let union_managed_dirs var (sep, dirs) (other_sep, other_dirs) =
  if not (Char.equal sep other_sep)
  then
    Code_error.raise
      "inconsistent separators for managed environment paths"
      [ "var", Var.to_dyn var; "sep", Dyn.char sep; "other_sep", Dyn.char other_sep ];
  sep, Path0.Build.Set.union dirs other_dirs
;;

let add_managed_dirs t ~var ~sep dirs =
  match dirs with
  | [] -> t
  | _ :: _ ->
    let dirs = sep, Path0.Build.Set.of_list dirs in
    let managed_dirs =
      Map.update t.managed_dirs var ~f:(function
        | None -> Some dirs
        | Some old -> Some (union_managed_dirs var old dirs))
    in
    { t with managed_dirs }
;;

let to_list { vars; _ } =
  Map.foldi vars ~init:[] ~f:(fun var value acc -> (var, Value.to_string value) :: acc)
;;

let render (var, value) = String.append_with_char (Var.to_string var) ~sep:'=' value
let to_unix t = List.map (to_list t) ~f:render

let to_windows_block t =
  match to_unix t with
  | [] -> "\000\000"
  | env ->
    let len = List.fold_left env ~init:1 ~f:(fun acc s -> acc + String.length s + 1) in
    let block = Buffer.create len in
    List.iter env ~f:(fun binding ->
      Buffer.add_string block binding;
      Buffer.add_char block '\000');
    Buffer.add_char block '\000';
    Buffer.contents block
;;

let map_of_unix arr =
  Array.to_list arr
  |> List.map ~f:(fun s ->
    match String.lsplit2 s ~on:'=' with
    | None ->
      Code_error.raise
        "Env.of_unix: entry without '=' found in the environment"
        [ "var", String s ]
    | Some (k, v) -> Var.of_string k, v)
  |> Map.of_list_multi
  |> Map.map ~f:(function
    | [] -> assert false
    | x :: _ -> x)
;;

let initial = of_map (map_of_unix (Unix.environment ()))
let of_unix u = of_map (map_of_unix u)

let add t ~var ~value =
  let vars =
    Map.update t.vars var ~f:(function
      | Some old when String.equal value (Value.to_string old) -> Some old
      | None | Some _ -> Some (Value.of_string value))
  in
  if vars == t.vars then t else { t with vars }
;;

let mem { vars; _ } ~var = Map.mem vars var

let remove t ~var =
  if Map.mem t.vars var then { t with vars = Map.remove t.vars var } else t
;;

let extend t ~vars =
  if Map.is_empty vars
  then t
  else { t with vars = Map.superpose (Map.map vars ~f:Value.of_string) t.vars }
;;

let extend_env x y =
  if is_empty y
  then x
  else if is_empty x
  then y
  else
    { vars = Map.superpose y.vars x.vars
    ; managed_dirs =
        Map.merge x.managed_dirs y.managed_dirs ~f:(fun var x y ->
          match x, y with
          | None, dirs | dirs, None -> dirs
          | Some x, Some y -> Some (union_managed_dirs var x y))
    }
;;

let to_dyn { vars; _ } = Map.to_dyn (fun value -> Dyn.string (Value.to_string value)) vars

let diff x y =
  { vars =
      Map.merge x.vars y.vars ~f:(fun _ vx vy ->
        match vy with
        | Some _ -> None
        | None -> vx)
  ; managed_dirs =
      Map.merge x.managed_dirs y.managed_dirs ~f:(fun _ x y ->
        match x, y with
        | None, _ -> None
        | Some dirs, None -> Some dirs
        | Some (sep, dirs), Some (other_sep, other_dirs) ->
          let dirs =
            if Char.equal sep other_sep
            then Path0.Build.Set.diff dirs other_dirs
            else dirs
          in
          if Path0.Build.Set.is_empty dirs then None else Some (sep, dirs))
  }
;;

let update t ~var ~f =
  match f (get t var) with
  | None -> remove t ~var
  | Some value -> add t ~var ~value
;;

let of_string_map m =
  String.Map.foldi m ~init:Map.empty ~f:(fun k v acc -> Map.set acc (Var.of_string k) v)
  |> of_map
;;

let iter { vars; _ } ~f =
  Map.iteri vars ~f:(fun var value -> f var (Value.to_string value))
;;

let to_map { vars; _ } = Map.map vars ~f:Value.to_string
