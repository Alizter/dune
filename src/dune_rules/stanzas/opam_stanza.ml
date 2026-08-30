open Import

type origin =
  | User
  | Lock

type t =
  { loc : Loc.t
  ; origin : origin
  ; package : Package.t
  ; depends : (Loc.t * Package.Name.t) list
  ; build : Dune_pkg.Lock_dir.Build_command.t option
  ; install : Dune_lang.Action.t option
  ; depexts : Dune_pkg.Lock_dir.Depexts.t list
  ; exported_env : String_with_vars.t Dune_lang.Action.Env_update.t list
  }

let decode =
  let open Dune_lang.Decoder in
  let package_decoder decoder =
    let version = 0, 1 in
    let env = Pform.Env.pkg Dune_lang.Pkg.syntax version in
    decoder
    |> Dune_lang.Syntax.set Dune_lang.Pkg.syntax (Active version)
    |> String_with_vars.set_decoding_env env
  in
  let package_action = package_decoder Dune_lang.Action.decode_pkg in
  fields
  @@ let+ loc = loc
     and+ package = Stanza_pkg.field ~stanza:"opam"
     and+ depends = field "depends" (repeat (located Package.Name.decode)) ~default:[]
     and+ build =
       field_o "build" package_action
       >>| Option.map ~f:(fun action -> Dune_pkg.Lock_dir.Build_command.Action action)
     and+ install = field_o "install" package_action
     and+ depexts =
       field "depexts" (repeat string) ~default:[]
       >>| fun external_package_names ->
       match external_package_names with
       | [] -> []
       | _ ->
         [ { Dune_pkg.Lock_dir.Depexts.external_package_names; enabled_if = `Always } ]
     and+ exported_env =
       field
         "exported_env"
         (package_decoder (repeat Dune_lang.Action.Env_update.decode))
         ~default:[]
     in
     { loc; origin = User; package; depends; build; install; depexts; exported_env }
;;

let target_dir t ~dir =
  Path.Build.L.relative
    dir
    [ ".opam"; Package.Name.to_string (Package.name t.package); "target" ]
;;

include Stanza.Make (struct
    type nonrec t = t

    include Poly
  end)
