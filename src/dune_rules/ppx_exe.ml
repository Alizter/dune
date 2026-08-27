open Import
open Memo.O

(* Encoded representation of a set of library names + scope *)
module Key : sig
  type encoded = Digest.t

  module Decoded : sig
    type scope = private
      { project : Loaded_project.Identity.t
      ; dir : Path.Local.t
      }

    type t = private
      { pps : Lib_name.t list
      ; scope : scope option
      }

    val of_libs : Lib.t list -> t Memo.t
  end

  val encode : Decoded.t -> encoded
  val decode : encoded -> Decoded.t
end = struct
  type encoded = Digest.t

  module Decoded = struct
    type scope =
      { project : Loaded_project.Identity.t
      ; dir : Path.Local.t
      }

    type t =
      { pps : Lib_name.t list
      ; scope : scope option
      }

    let equal_scope x y =
      Loaded_project.Identity.equal x.project y.project && Path.Local.equal x.dir y.dir
    ;;

    let scope_repr =
      Repr.record
        "ppx-scope"
        [ Repr.field "project" Loaded_project.Identity.repr ~get:(fun t -> t.project)
        ; Repr.field "dir" Path.Local.repr ~get:(fun t -> t.dir)
        ]
    ;;

    let equal x y =
      List.equal Lib_name.equal x.pps y.pps && Option.equal equal_scope x.scope y.scope
    ;;

    let to_string { pps; scope } =
      let s = String.enumerate_and (List.map pps ~f:Lib_name.to_string) in
      match scope with
      | None -> s
      | Some { project; dir } ->
        sprintf
          "%s (in scope: %s at %s)"
          s
          (Loaded_project.Identity.to_dyn project |> Dyn.to_string)
          (Path.Local.to_string_maybe_quoted dir)
    ;;

    let of_libs libs =
      let pps =
        (let compare a b = Lib_name.compare (Lib.name a) (Lib.name b) in
         List.sort libs ~compare)
        |> List.map ~f:Lib.name
      in
      let+ scope =
        Memo.List.fold_left libs ~init:None ~f:(fun acc lib ->
          let info = Lib.info lib in
          let add_scope project =
            let output_dir = Path.as_in_build_dir_exn (Lib_info.src_dir info) in
            let+ loaded_project = Dune_load.find_loaded_project ~dir:output_dir in
            if not (Dune_project.equal project (Loaded_project.project loaded_project))
            then
              Code_error.raise
                "PPX library project does not match its loaded project"
                [ "library_project", Dune_project.to_dyn project
                ; "loaded_project", Loaded_project.to_dyn loaded_project
                ];
            let source_dir =
              Loaded_project.source_path loaded_project output_dir |> Option.value_exn
            in
            let dir =
              Source_path.descendant
                source_dir
                ~of_:(Loaded_project.source_root loaded_project)
              |> Option.value_exn
            in
            let scope = { project = Loaded_project.identity loaded_project; dir } in
            Option.merge acc (Some scope) ~f:(fun a b ->
              if not (Loaded_project.Identity.equal a.project b.project)
              then
                Code_error.raise
                  "PPX libraries belong to different loaded projects"
                  [ "first", Loaded_project.Identity.to_dyn a.project
                  ; "second", Loaded_project.Identity.to_dyn b.project
                  ];
              { a with dir = Ordering.min Path.Local.compare a.dir b.dir })
          in
          match Lib_info.status info with
          | Installed_private | Installed -> Memo.return acc
          | Private (project, _) -> add_scope project
          | Public (project, _) ->
            let output_dir = Path.as_in_build_dir_exn (Lib_info.src_dir info) in
            let* loaded_project = Dune_load.find_loaded_project ~dir:output_dir in
            (match Build_partition.purpose (Loaded_project.partition loaded_project) with
             | Workspace -> Memo.return acc
             | Mounted -> add_scope project))
      in
      { pps; scope }
    ;;
  end

  let reverse_table : (Digest.t, Decoded.t) Table.t = Table.create (module Digest) 128

  let encode ({ Decoded.pps; scope } as x) =
    let y =
      Digest.repr Repr.(pair (list Lib_name.repr) (option Decoded.scope_repr)) (pps, scope)
    in
    match Table.find reverse_table y with
    | None ->
      Table.set reverse_table y x;
      y
    | Some x' ->
      if Decoded.equal x x'
      then y
      else
        User_error.raise
          [ Pp.textf "Hash collision between set of ppx drivers:"
          ; Pp.textf "- cache : %s" (Decoded.to_string x')
          ; Pp.textf "- fetch : %s" (Decoded.to_string x)
          ]
  ;;

  let decode y =
    match Table.find reverse_table y with
    | Some x -> x
    | None ->
      User_error.raise
        [ Pp.textf
            "I don't know what ppx rewriters set %s correspond to."
            (Digest.to_string y)
        ]
  ;;
end

let ppx_exe_path root ~key = Path.Build.relative root (".ppx/" ^ key ^ "/ppx.exe")

let ppx_driver_exe (ctx : Context.t) libs =
  let* decoded = Key.Decoded.of_libs libs
  and* host = Context.host ctx in
  let key = Digest.to_string (Key.encode decoded) in
  let+ root =
    match decoded.scope with
    | None -> Memo.return (Context.build_dir host)
    | Some { project; _ } ->
      let+ loaded_project =
        Dune_load.find_loaded_project_by_identity
          ~context:(Context.name host)
          ~identity:project
      in
      (match Build_partition.purpose (Loaded_project.partition loaded_project) with
       | Workspace -> Context.build_dir host
       | Mounted -> Loaded_project.output_root loaded_project)
  in
  ppx_exe_path root ~key
;;

let get_ppx_exe ctx ~scope pps =
  let open Resolve.Memo.O in
  let* libs = Lib.DB.resolve_pps (Scope.libs scope) pps in
  ppx_driver_exe ctx libs |> Resolve.Memo.lift_memo
;;
