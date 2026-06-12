open Import
open Memo.O

type 'a t = Context_name.t -> 'a Memo.t

let all =
  Memo.lazy_ ~name:"context-db"
  @@ fun () ->
  let+ workspace = Workspace.workspace () in
  let contexts =
    List.concat_map workspace.contexts ~f:(fun (context : Workspace.Context.t) ->
      let base = Workspace.Context.base context in
      let native, targets, mounts = base.name, base.targets, base.mounts in
      let cross_target_entries native_name =
        List.filter_map targets ~f:(function
          | Native -> None
          | Named { name = toolchain; _ } ->
            let name = Context_name.target native_name ~toolchain in
            Some (name, `Target (context, toolchain)))
      in
      let workspace_entries = (native, `Native context) :: cross_target_entries native in
      let mount_entries =
        List.concat_map mounts ~f:(fun mount ->
          let mount_native_name =
            Context_name.target
              native
              ~toolchain:(Workspace.Context.Mount.internal_name mount)
          in
          (mount_native_name, `Native context)
          :: List.map (cross_target_entries mount_native_name) ~f:(fun (n, v) -> n, v))
      in
      workspace_entries @ mount_entries)
  in
  Context_name.Map.of_list_exn contexts
;;

let list () = Memo.Lazy.force all >>| Context_name.Map.keys

let create_db ?cutoff ~name f =
  let cutoff = Option.map cutoff ~f:(fun equal -> Context_name.Map.equal ~equal) in
  let map =
    Memo.lazy_ ~name ?cutoff (fun () ->
      let+ map = Memo.Lazy.force all in
      Context_name.Map.mapi map ~f)
  in
  Staged.stage (fun context ->
    let+ map = Memo.Lazy.force map in
    Context_name.Map.find map context)
;;

let or_invalid ctx = function
  | Some s -> s
  | None -> Code_error.raise "invalid context" [ "context", Context_name.to_dyn ctx ]
;;

let create_by_name ~name f =
  let f = Staged.unstage @@ create_db ~name (fun k _ -> f k) in
  Staged.stage (fun name -> f name >>= or_invalid name)
;;

let profile =
  let profile =
    create_db ~cutoff:Profile.equal ~name:"profile" (fun _ v ->
      match v with
      | `Native ctx | `Target (ctx, _) -> (Workspace.Context.base ctx).profile)
    |> Staged.unstage
  in
  fun ctx -> profile ctx >>| or_invalid ctx
;;

let valid =
  let find =
    create_db ~cutoff:Unit.equal ~name:"context-validation" (fun _ v ->
      match v with
      | `Native _ | `Target (_, _) -> ())
    |> Staged.unstage
  in
  fun ctx -> find ctx >>| Option.is_some
;;
