open Import

let prefix = "_"
let suffix = "+lockfile"

let make resolver =
  Context_name.of_string
    (sprintf "%s%s%s" prefix (Context_name.to_string resolver) suffix)
;;

let resolver context =
  Context_name.to_string context
  |> String.drop_prefix_and_suffix ~prefix ~suffix
  |> Option.bind ~f:Context_name.of_string_opt
;;

let resolver_or_self context = Option.value (resolver context) ~default:context
