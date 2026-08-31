open Import

type selection =
  { scopes : Dune_lang.Scope_stanza.t Source_path.Map.t
  ; package_dirs : Source_path.t Package.Id.Map.t
  }

type t = selection list

let empty = []
let is_empty = List.is_empty
let intersect a b = a @ b

let package_dir package =
  match Package.exclusive_dir package with
  | Some (_, dir) -> dir
  | None -> Package.dir package
;;

let name_is_visible_at_dir selection ~dir name =
  let rec loop dir =
    let visible_here =
      match Source_path.Map.find selection.scopes dir with
      | None -> true
      | Some scope -> Package.Name.Set.mem (Dune_lang.Scope_stanza.packages scope) name
    in
    visible_here
    &&
    match Source_path.parent dir with
    | None -> true
    | Some parent -> loop parent
  in
  loop dir
;;

let package_id_dir selection (package : Package.Id.t) =
  Package.Id.Map.find selection.package_dirs package |> Option.value ~default:package.dir
;;

let package_id_is_visible selection package =
  name_is_visible_at_dir
    selection
    ~dir:(package_id_dir selection package)
    (Package.Id.name package)
;;

let is_package_visible t package =
  let package = Package.id package in
  List.for_all t ~f:(fun selection -> package_id_is_visible selection package)
;;

let is_stanza_visible t ~dir package =
  List.for_all t ~f:(fun selection ->
    package_id_is_visible selection package
    && name_is_visible_at_dir selection ~dir (Package.Id.name package))
;;

let create ~scopes ~packages =
  let scopes = Source_path.Map.of_list_exn scopes in
  if Source_path.Map.is_empty scopes
  then empty
  else (
    let package_dirs =
      List.fold_left packages ~init:Package.Id.Map.empty ~f:(fun dirs package ->
        let id = Package.id package in
        let dir = package_dir package in
        Package.Id.Map.update dirs id ~f:(function
          | None -> Some dir
          | Some previous ->
            if Source_path.equal previous dir
            then Some previous
            else
              Code_error.raise
                "Package has inconsistent scope directories"
                [ "package", Package.Id.to_dyn id
                ; "first_dir", Source_path.to_dyn previous
                ; "second_dir", Source_path.to_dyn dir
                ]))
    in
    let package_locations =
      List.fold_left packages ~init:Package.Name.Map.empty ~f:(fun locations package ->
        Package.Name.Map.add_multi locations (Package.name package) (package_dir package))
    in
    Source_path.Map.iteri scopes ~f:(fun scope_dir scope ->
      let unavailable =
        Package.Name.Set.filter (Dune_lang.Scope_stanza.packages scope) ~f:(fun name ->
          match Package.Name.Map.find package_locations name with
          | None -> true
          | Some dirs ->
            not
              (List.exists dirs ~f:(fun dir ->
                 Source_path.is_descendant dir ~of_:scope_dir)))
      in
      match Package.Name.Set.to_list unavailable with
      | [] -> ()
      | names ->
        User_error.raise
          ~loc:(Dune_lang.Scope_stanza.loc scope)
          [ Pp.textf
              "The following packages are not defined beneath this scope: %s"
              (List.map names ~f:Package.Name.to_string |> String.concat ~sep:", ")
          ; Pp.textf "Scope directory: %s" (Source_path.to_string_maybe_quoted scope_dir)
          ]);
    [ { scopes; package_dirs } ])
;;

let filter_project t project =
  (* Keep the project's canonical package and exclusive-directory maps. They are
     needed to decode scoped-out stanzas and to build unowned implementation
     stanzas; [Dune_project.packages] is the active package-facing view. *)
  if is_empty t
  then project
  else (
    let packages = Dune_project.including_hidden_packages project in
    let visible name =
      match Package.Name.Map.find packages name with
      | None -> false
      | Some package -> is_package_visible t package
    in
    if
      Dune_project.packages project
      |> Package.Name.Map.values
      |> List.for_all ~f:(fun package -> visible (Package.name package))
    then project
    else Dune_project.filter_packages project ~f:visible)
;;
