open Import
open Memo.O

type opam =
  { stanza : Opam_stanza.t
  ; paths : Path.Build.t Package_deps.Paths.t
  }

type t =
  { context : Context_name.t
  ; user_opam_packages : opam Package.Name.Map.t
  }

type any_package =
  | Local of Package.t
  | Installed of Dune_package.t
  | Opam of opam

let user_opam_paths (stanza : Opam_stanza.t) ~output_dir =
  let name = Package.name stanza.package in
  let target_dir = Opam_stanza.target_dir stanza ~dir:output_dir in
  let root = Path.Build.parent_exn target_dir in
  let paths = Package_deps.Paths.of_root name ~root ~relative:Path.Build.relative in
  { paths with source_dir = output_dir; target_dir }
;;

let load_user_opam_packages context =
  let* dune_files = Dune_load.workspace_dune_files context in
  let+ packages =
    Memo.List.concat_map dune_files ~f:(fun dune_file ->
      let+ stanzas = Dune_file.find_stanzas dune_file Opam_stanza.key in
      List.map stanzas ~f:(fun (stanza : Opam_stanza.t) ->
        let paths = user_opam_paths stanza ~output_dir:(Dune_file.output_dir dune_file) in
        Package.name stanza.package, { stanza; paths }))
  in
  Package.Name.Map.of_list_reduce packages ~f:(fun first second ->
    User_error.raise
      ~loc:second.stanza.loc
      [ Pp.textf
          "Package %s has more than one opam stanza"
          (Package.Name.to_string (Package.name second.stanza.package))
      ; Pp.textf "The first stanza is at %s" (Loc.to_file_colon_line first.stanza.loc)
      ])
;;

let user_opam_packages =
  Per_context.create_by_name ~name:"user-opam-packages" load_user_opam_packages
  |> Staged.unstage
;;

let mounted_opam_paths mounted (stanza : Opam_stanza.t) =
  let name = Package.name stanza.package in
  let candidate = Pkg_sources.Mounted.candidate mounted in
  let root =
    Path.Build.L.relative
      (Pkg_sources.Candidate.artifact_root candidate)
      [ ".opam"; Package.Name.to_string name ]
  in
  let paths = Package_deps.Paths.of_root name ~root ~relative:Path.Build.relative in
  { paths with source_dir = Pkg_sources.Mounted.working_dir mounted }
;;

let find_package { context; user_opam_packages } pkg =
  let* packages = Dune_load.packages () in
  match Package.Name.Map.find packages pkg with
  | Some package ->
    (match Package.Name.Map.find user_opam_packages pkg with
     | None -> Memo.return (Some (Local package))
     | Some opam -> Memo.return (Some (Opam opam)))
  | None ->
    Pkg_sources.find_mounted context pkg
    >>= (function
     | Some mounted ->
       (match Pkg_sources.Mounted.kind mounted with
        | Dune ->
          let package =
            Pkg_sources.Mounted.projects mounted
            |> List.find_map ~f:(fun (project, _) ->
              Package.Name.Map.find (Dune_project.including_hidden_packages project) pkg)
            |> Option.value_exn
          in
          Memo.return (Some (Local package))
        | Opam stanza ->
          let paths = mounted_opam_paths mounted stanza in
          Memo.return (Some (Opam { stanza; paths })))
     | None ->
       Lock_dir.lock_dir_active context
       >>= (function
        | true -> Memo.return None
        | false ->
          let* findlib = Findlib.create context in
          Findlib.find_root_package findlib pkg
          >>= (function
           | Ok p -> Memo.return @@ Some (Installed p)
           | Error (Invalid_dune_package user_message) ->
             User_error.raise [ User_message.pp user_message ]
           | Error Not_found -> Memo.return None)))
;;

let create context =
  let+ user_opam_packages = user_opam_packages context in
  { context; user_opam_packages }
;;

let user_opam_packages t = t.user_opam_packages

let section_of_any_package_site any_package pkg_name loc site =
  let sites =
    match any_package with
    | Opam _ ->
      (* TODO We should be able to extract this information after the package
         is built *)
      Site.Map.empty
    | Local p -> Package.sites p
    | Installed p -> p.sites
  in
  match Site.Map.find sites site with
  | Some section -> section
  | None ->
    User_error.raise
      ~loc
      [ Pp.textf
          "Package %s doesn't define a site %s"
          (Package.Name.to_string pkg_name)
          (Site.to_string site)
      ]
;;

let section_of_site t ~loc ~pkg:pkg_name ~site =
  find_package t pkg_name
  >>| function
  | None ->
    User_error.raise
      ~loc
      [ Pp.textf "The package %s is not found" (Package.Name.to_string pkg_name) ]
  | Some pkg -> section_of_any_package_site pkg pkg_name loc site
;;
