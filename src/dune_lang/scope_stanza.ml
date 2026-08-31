open Import

type t =
  { loc : Loc.t
  ; packages : Package_name.Set.t
  }

let make ~loc ~packages = { loc; packages }
let loc t = t.loc
let packages t = t.packages

let decode =
  let open Decoder in
  fields
  @@ let+ loc = loc
     and+ packages = field "packages" (repeat (located Package_name.decode)) in
     let packages =
       List.fold_left
         packages
         ~init:Package_name.Set.empty
         ~f:(fun packages (loc, name) ->
           if Package_name.Set.mem packages name
           then
             User_error.raise
               ~loc
               [ Pp.textf "Package %S is listed twice." (Package_name.to_string name) ]
           else Package_name.Set.add packages name)
     in
     { loc; packages }
;;
