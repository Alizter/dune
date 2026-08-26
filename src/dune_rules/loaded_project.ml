open Import

module Identity = struct
  type t =
    | Workspace of Path.Source.t
    | Mounted of
        { lock : Dune_digest.t
        ; package : Package.Name.t
        ; project_root : Path.Local.t
        }

  let workspace root = Workspace root
  let mounted ~lock ~package ~project_root = Mounted { lock; package; project_root }

  let equal a b =
    match a, b with
    | Workspace a, Workspace b -> Path.Source.equal a b
    | Mounted a, Mounted b ->
      Dune_digest.equal a.lock b.lock
      && Package.Name.equal a.package b.package
      && Path.Local.equal a.project_root b.project_root
    | Workspace _, Mounted _ | Mounted _, Workspace _ -> false
  ;;

  let repr =
    let digest_repr = Repr.view Repr.string ~to_:Dune_digest.to_string in
    Repr.variant
      "loaded-project-identity"
      [ Repr.case "Workspace" Path.Source.repr ~proj:(function
          | Workspace root -> Some root
          | Mounted _ -> None)
      ; Repr.case
          "Mounted"
          (Repr.T3.repr digest_repr Package.Name.repr Path.Local.repr)
          ~proj:(function
          | Mounted { lock; package; project_root } -> Some (lock, package, project_root)
          | Workspace _ -> None)
      ]
  ;;

  let digest t = Dune_digest.repr repr t

  let to_dyn = function
    | Workspace root -> Dyn.variant "Workspace" [ Path.Source.to_dyn root ]
    | Mounted { lock; package; project_root } ->
      Dyn.variant
        "Mounted"
        [ Dyn.record
            [ "lock", Dune_digest.to_dyn lock
            ; "package", Package.Name.to_dyn package
            ; "project_root", Path.Local.to_dyn project_root
            ]
        ]
  ;;
end

type t =
  { project : Dune_project.t
  ; identity : Identity.t
  ; source_root : Source_path.t
  ; loaded_source : Loaded_source.t option
  ; partition : Build_partition.t
  ; output_root : Path.Build.t
  ; visible_packages : Package.Name.Set.t option
  }

let create
      ~project
      ~identity
      ~source_root
      ~loaded_source
      ~partition
      ~output_root
      ~visible_packages
  =
  (match source_root, loaded_source with
   | Source_path.Workspace _, None | Build _, Some _ -> ()
   | Workspace _, Some _ | Build _, None ->
     Code_error.raise
       "Loaded project source root and backing source disagree"
       [ "source_root", Source_path.to_dyn source_root
       ; "loaded_source", Dyn.option Loaded_source.to_dyn loaded_source
       ]);
  if
    not
      (Path.is_descendant
         (Path.build output_root)
         ~of_:(Path.build (Build_partition.output_root partition)))
  then
    Code_error.raise
      "Loaded_project output root is outside its build partition"
      [ "output_root", Path.Build.to_dyn output_root
      ; "partition", Build_partition.to_dyn partition
      ];
  { project
  ; identity
  ; source_root
  ; loaded_source
  ; partition
  ; output_root
  ; visible_packages
  }
;;

let project t = t.project
let identity t = t.identity
let source_root t = t.source_root
let loaded_source t = t.loaded_source
let partition t = t.partition
let output_root t = t.output_root
let visible_packages t = t.visible_packages

let output_path t source_path =
  Source_path.descendant source_path ~of_:t.source_root
  |> Option.map ~f:(Path.Build.append_local t.output_root)
;;

let source_path t output_path =
  Path.drop_prefix (Path.build output_path) ~prefix:(Path.build t.output_root)
  |> Option.map ~f:(Source_path.append_local t.source_root)
;;

let to_dyn t =
  Dyn.record
    [ "identity", Identity.to_dyn t.identity
    ; "source_root", Source_path.to_dyn t.source_root
    ; "loaded_source", Dyn.option Loaded_source.to_dyn t.loaded_source
    ; "partition", Build_partition.to_dyn t.partition
    ; "output_root", Path.Build.to_dyn t.output_root
    ; "visible_packages", Dyn.option Package.Name.Set.to_dyn t.visible_packages
    ]
;;
