open Import

(* This file is licensed under The MIT License *)
(* (c) MINES ParisTech 2018-2019               *)
(* (c) INRIA 2020                              *)
(* Written by: Emilio Jesús Gallego Arias *)

module Id = struct
  module T = struct
    type t =
      { path : Path.t
      ; name : Coq_lib_name.t
      }

    let compare t { path; name } =
      let open Ordering.O in
      let= () = Path.compare t.path path in
      Coq_lib_name.compare t.name name

    let to_dyn { path; name } =
      Dyn.record
        [ ("path", Path.to_dyn path); ("name", Coq_lib_name.to_dyn name) ]
  end

  include T

  let pp { path; name } =
    Pp.concat ~sep:Pp.space
      [ Pp.textf "theory %s in" (Coq_lib_name.to_string name); Path.pp path ]

  let create ~path ~name = { path; name }

  module C = Comparable.Make (T)
  module Top_closure = Top_closure.Make (C.Set) (Resolve)

  let top_closure ~key ~deps xs = Top_closure.top_closure ~key ~deps xs
end

include struct
  (* ocaml doesn't allow annotating the field directly *)
  [@@@ocaml.warning "-69"]

  type t =
    { loc : Loc.t
    ; boot : t option Resolve.t
    ; id : Id.t
    ; implicit : bool (* Only useful for the stdlib *)
    ; use_stdlib : bool
          (* whether this theory uses the stdlib, eventually set to false for all libs *)
    ; src_root : Path.t
    ; obj_root : Path.t
    ; theories : (Loc.t * t) list Resolve.t
    ; libraries : (Loc.t * Lib.t) list Resolve.t
    ; theories_closure : t list Resolve.t Lazy.t
    ; package : Package.t option
    }
end

let name l = l.id.name

let implicit l = l.implicit

let src_root l = l.src_root

let obj_root l = l.obj_root

let libraries l = l.libraries

let package l = l.package

module Error = struct
  let annots =
    User_message.Annots.singleton User_message.Annots.needs_stack_trace ()

  let duplicate_theory_name name1 name2 =
    let loc1, name = name1 in
    let loc2, _ = name2 in
    User_error.raise
      [ Pp.textf "Coq theory %s is defined twice:" (Coq_lib_name.to_string name)
      ; Pp.textf "- %s" (Loc.to_file_colon_line loc1)
      ; Pp.textf "- %s" (Loc.to_file_colon_line loc2)
      ]

  let incompatible_boot id id' =
    let pp_lib (id : Id.t) = Pp.seq (Pp.text "- ") (Id.pp id) in
    User_message.make ~annots
      [ Pp.textf "The following theories use incompatible boot libraries"
      ; pp_lib id'
      ; pp_lib id
      ]
    |> Resolve.fail

  let theory_not_found ~loc name =
    let name = Coq_lib_name.to_string name in
    Resolve.Memo.fail
    @@ User_message.make ~annots ~loc [ Pp.textf "Theory %s not found" name ]

  let hidden_without_composition ~loc name =
    let name = Coq_lib_name.to_string name in
    Resolve.Memo.fail
    @@ User_message.make ~annots ~loc
         [ Pp.textf
             "Theory %s not found in the current scope. Upgrade coq lang to \
              0.4 to enable scope composition."
             name
         ]

  let private_deps_not_allowed ~loc name =
    let name = Coq_lib_name.to_string name in
    Resolve.Memo.fail
    @@ User_message.make ~loc
         [ Pp.textf
             "Theory %S is private, it cannot be a dependency of a public \
              theory. You need to associate %S to a package."
             name name
         ]

  let duplicate_boot_lib theories =
    let open Coq_stanza.Theory in
    let name (t : Coq_stanza.Theory.t) =
      let name = Coq_lib_name.to_string (snd t.name) in
      Pp.textf "%s at %s" name (Loc.to_file_colon_line t.buildable.loc)
    in
    User_error.raise
      [ Pp.textf "Cannot have more than one boot theory in scope:"
      ; Pp.enumerate theories ~f:name
      ]
end

let top_closure =
  let key t = t.id in
  let deps t = t.theories |> Resolve.map ~f:(List.map ~f:snd) in
  fun theories ->
    let open Resolve.O in
    Id.top_closure theories ~key ~deps >>= function
    | Ok s -> Resolve.return s
    | Error _ -> assert false

module DB = struct
  type lib = t

  type entry =
    | Theory of Path.Build.t
    | Redirect of t

  and t =
    { parent : t option
    ; resolve :
           Coq_lib_name.t
        -> [ `Redirect of t
           | `Theory of Lib.DB.t * Path.Build.t * Coq_stanza.Theory.t
           | `Stdlib of lib
           | `User_contrib of lib
           | `Not_found
           ]
    ; boot : (Loc.t * lib Resolve.t Memo.Lazy.t) option
    }

  module rec R : sig
    val resolve :
         t
      -> coq_lang_version:Dune_sexp.Syntax.Version.t
      -> Loc.t * Coq_lib_name.t
      -> lib Resolve.Memo.t
  end = struct
    open R

    let rec boot coq_db =
      match coq_db.boot with
      | Some (_, boot) ->
        Memo.Lazy.force boot |> Resolve.Memo.map ~f:Option.some
      | None -> (
        match coq_db.parent with
        | None -> Resolve.Memo.return None
        | Some parent -> boot parent)

    let create_from_stanza =
      let create_from_stanza_impl (coq_db, db, dir, (s : Coq_stanza.Theory.t)) =
        let name = snd s.name in
        let id = Id.create ~path:dir ~name in
        let coq_lang_version = s.buildable.coq_lang_version in
        let open Memo.O in
        let* boot = if s.boot then Resolve.Memo.return None else boot coq_db in
        let allow_private_deps = Option.is_none s.package in
        let use_stdlib = s.buildable.use_stdlib in
        let+ libraries =
          Resolve.Memo.List.map s.buildable.plugins ~f:(fun (loc, lib) ->
              let open Resolve.Memo.O in
              let* lib = Lib.DB.resolve db (loc, lib) in
              let+ () =
                Resolve.Memo.lift
                @@
                if allow_private_deps then Resolve.return ()
                else
                  match
                    let info = Lib.info lib in
                    let status = Lib_info.status info in
                    Lib_info.Status.is_private status
                  with
                  | false -> Resolve.return ()
                  | true ->
                    Resolve.fail
                    @@ User_message.make ~loc
                         [ Pp.textf
                             "private theory %s may not depend on a public \
                              library"
                             (Coq_lib_name.to_string name)
                         ]
              in
              (loc, lib))
        and+ theories =
          let check_boot (lib : lib) =
            let open Resolve.O in
            let* boot = boot in
            match boot with
            | None -> Resolve.return ()
            | Some boot -> (
              let* boot' = lib.boot in
              match boot' with
              | None -> Resolve.return ()
              | Some boot' -> (
                match Id.compare boot.id boot'.id with
                | Eq -> Resolve.return ()
                | _ -> Error.incompatible_boot lib.id id))
          in
          Resolve.Memo.List.map s.buildable.theories
            ~f:(fun (loc, theory_name) ->
              let open Resolve.Memo.O in
              let* theory =
                resolve ~coq_lang_version coq_db (loc, theory_name)
              in
              let* () = Resolve.Memo.lift @@ check_boot theory in
              let+ () =
                if allow_private_deps then Resolve.Memo.return ()
                else
                  match theory.package with
                  | Some _ -> Resolve.Memo.return ()
                  | None -> Error.private_deps_not_allowed ~loc theory_name
              in
              (loc, theory))
        in
        let theories =
          let open Resolve.O in
          let* boot = boot in
          match boot with
          | Some boot when use_stdlib && not s.boot ->
            let+ theories = theories in
            (boot.loc, boot) :: theories
          | Some _ | None -> theories
        in
        let map_error x =
          let human_readable_description () = Id.pp id in
          Resolve.push_stack_frame ~human_readable_description x
        in
        let theories = map_error theories in
        let libraries = map_error libraries in
        { loc = s.buildable.loc
        ; boot
        ; id
        ; use_stdlib
        ; implicit = s.boot
        ; obj_root = dir
        ; src_root = dir
        ; theories
        ; libraries
        ; theories_closure =
            lazy
              (Resolve.bind theories ~f:(fun theories ->
                   List.map theories ~f:snd |> top_closure))
        ; package = s.package
        }
      in
      let module Input = struct
        type nonrec t = t * Lib.DB.t * Path.t * Coq_stanza.Theory.t

        let equal (coq_db, ml_db, path, stanza) (coq_db', ml_db', path', stanza')
            =
          coq_db == coq_db' && ml_db == ml_db' && Path.equal path path'
          && stanza == stanza'

        let hash = Poly.hash

        let to_dyn = Dyn.opaque
      end in
      let memo =
        Memo.create "create-from-stanza"
          ~human_readable_description:(fun (_, _, path, theory) ->
            Id.pp (Id.create ~path ~name:(snd theory.name)))
          ~input:(module Input)
          create_from_stanza_impl
      in
      fun coq_db db dir stanza -> Memo.exec memo (coq_db, db, dir, stanza)

    let rec find coq_db name =
      match coq_db.resolve name with
      | `Theory (db, dir, stanza) -> `Theory (db, dir, stanza)
      | `Redirect coq_db -> find coq_db name
      | `Stdlib lib -> `Stdlib lib
      | `User_contrib lib -> `User_contrib lib
      | `Not_found -> (
        match coq_db.parent with
        | None -> `Not_found
        | Some parent -> find parent name)

    let find coq_db ~coq_lang_version name =
      match find coq_db name with
      | `Not_found -> `Not_found
      (* Composing with installed theories should come past 0.8 *)
      | (`Stdlib lib | `User_contrib lib) when coq_lang_version >= (0, 8) ->
        `Found_lib lib
      | `Stdlib _ | `User_contrib _ -> `Not_found
      (* Composing with theories in the same project should come past 0.4 *)
      | `Theory (mldb, dir, stanza) when coq_lang_version >= (0, 4) ->
        `Found_stanza (mldb, dir, stanza)
      | `Theory (mldb, dir, stanza) -> (
        match coq_db.resolve name with
        | `Not_found -> `Hidden
        | `Theory _ | `Redirect _ | `Stdlib _ | `User_contrib _ ->
          `Found_stanza (mldb, dir, stanza))

    let resolve coq_db ~coq_lang_version (loc, name) =
      match find coq_db ~coq_lang_version name with
      | `Not_found -> Error.theory_not_found ~loc name
      | `Hidden -> Error.hidden_without_composition ~loc name
      | `Found_stanza (db, dir, stanza) ->
        let open Memo.O in
        let+ theory = create_from_stanza coq_db db (Path.build dir) stanza in
        let open Resolve.O in
        let* (_ : (Loc.t * Lib.t) list) = theory.libraries in
        let+ (_ : (Loc.t * lib) list) = theory.theories in
        theory
      | `Found_lib lib -> Resolve.Memo.return lib
  end

  include R

  let rec boot_library_finder t =
    match t.boot with
    | None -> (
      match t.parent with
      | None -> None
      | Some parent -> boot_library_finder parent)
    | Some (loc, lib) -> Some (loc, lib)

  let boot_library t =
    (* Check if a database and its parents have the boot flag *)
    match boot_library_finder t with
    | None -> Resolve.Memo.return None
    | Some (loc, lib) ->
      let open Memo.O in
      let+ lib = Memo.Lazy.force lib in
      Resolve.map lib ~f:(fun lib -> Some (loc, lib))

  (* Should we register errors and printers, or raise is OK? *)
  let create_from_coqlib_stanzas ~(parent : t option) ~find_db
      (entries : (Coq_stanza.Theory.t * entry) list) =
    let t = Fdecl.create Dyn.opaque in
    let boot =
      let boot =
        match
          List.find_all entries
            ~f:(fun ((theory : Coq_stanza.Theory.t), _entry) -> theory.boot)
        with
        | [] -> None
        | [ ((theory : Coq_stanza.Theory.t), _entry) ] ->
          Some
            ( theory.buildable.loc
            , theory.name
            , theory.buildable.coq_lang_version )
        | boots ->
          let stanzas = List.map boots ~f:fst in
          Error.duplicate_boot_lib stanzas
      in
      match boot with
      | None -> None
      | Some (loc, name, coq_lang_version) ->
        let lib =
          Memo.lazy_ (fun () ->
              let t = Fdecl.get t in
              resolve t ~coq_lang_version name)
        in
        Some (loc, lib)
    in
    let resolve =
      let map =
        match
          Coq_lib_name.Map.of_list_map entries
            ~f:(fun ((theory : Coq_stanza.Theory.t), entry) ->
              (snd theory.name, (theory, entry)))
        with
        | Ok m -> m
        | Error (_name, (theory1, _entry1), (theory2, _entry2)) ->
          Error.duplicate_theory_name theory1.name theory2.name
      in
      fun name ->
        match Coq_lib_name.Map.find map name with
        | None -> `Not_found
        | Some (theory, entry) -> (
          match entry with
          | Theory dir -> `Theory (find_db dir, dir, theory)
          | Redirect db -> `Redirect db)
    in
    Fdecl.set t { boot; resolve; parent };
    Fdecl.get t

  let find_many t theories ~coq_lang_version =
    Resolve.Memo.List.map theories ~f:(resolve ~coq_lang_version t)

  let requires_for_user_written db theories ~coq_lang_version =
    let open Memo.O in
    let+ theories =
      Resolve.Memo.List.map theories ~f:(resolve ~coq_lang_version db)
    in
    Resolve.O.(theories >>= top_closure)

  let empty_db =
    let resolve _ = `Not_found in
    { parent = None; resolve; boot = None }

  let stdlib_lib ~coqlib =
    let theories_dir =
      Path.append_local coqlib (Path.Local.of_string "theories")
    in
    Memo.return
    @@ { loc = Loc.none
       ; boot = Resolve.return None
       ; id = Id.create ~path:theories_dir ~name:(Coq_lib_name.of_string "Coq")
       ; implicit = true (* TODO do we want to keep implicit for now? *)
       ; use_stdlib = false
       ; src_root = theories_dir
       ; obj_root = theories_dir
       ; theories = Resolve.return [] (* Stdlib has no theories deps *)
       ; libraries =
           (* Stdlib does have some libraries deps, but these can be ignored *)
           Resolve.return []
       ; theories_closure =
           (* The closure of the theories deps is empty *)
           lazy (Resolve.return [])
       ; package =
           None (* TODO: this should be the coq package (or coq-stdlib?) *)
       }

  (* This generates a map indexed by Coq_lib_names which pick out subdirectories
     recursively using the coq_lib_name. This is used only for scanning
     user-contrib and gernating "theories" from the existing directories. *)
  let rec subdirectory_map name dir : Path.t Coq_lib_name.Map.t Memo.t =
    (* Printf.printf "Making subdirectory map: %s %s\n" (Coq_lib_name.to_string name)
       (Path.to_string_maybe_quoted dir); *)
    let open Memo.O in
    (* TODO using exn here; remove *)
    let* dir_exists = Fs_memo.path_kind (Path.as_outside_build_dir_exn dir) in
    match dir_exists with
    | Ok Unix.S_DIR -> (
      let* dir_contents =
        Fs_memo.dir_contents (Path.as_outside_build_dir_exn dir)
      in
      match dir_contents with
      | Ok x ->
        let dir_files =
          List.filter_map (Fs_cache.Dir_contents.to_list x)
            ~f:(fun (file, kind) ->
              match kind with
              | Unix.S_DIR -> Some file
              | _ -> None)
        in
        let prefix_entries = Coq_lib_name.Map.singleton name dir in
        let+ subdirs_entries =
          List.map dir_files ~f:(fun file ->
              let name = Coq_lib_name.append name file in
              let dir = Path.append_local dir (Path.Local.of_string file) in
              subdirectory_map name dir)
          |> Memo.all
        in
        List.fold_left
          (prefix_entries :: subdirs_entries)
          ~init:Coq_lib_name.Map.empty ~f:Coq_lib_name.Map.union_exn
      | Error _ ->
        (* TODO Ignore errors for now *)
        Memo.return Coq_lib_name.Map.empty)
    | Error x ->
      User_error.raise
        [ Pp.text "System error encountered when finding coqlib:"
        ; Unix_error.Detailed.pp x
        ]
    | _ ->
      Code_error.raise "subdirectory_map: dir does not exist"
        [ ("name", Coq_lib_name.to_dyn name); ("dir", Path.to_dyn dir) ]

  let lib_of_user_contrib_name name path : lib =
    { loc = Loc.none
    ; boot = Resolve.return None
    ; id = Id.create ~name ~path
    ; implicit = false
    ; use_stdlib = false
    ; src_root = path
    ; obj_root = path
    ; theories =
        Resolve.return [] (* These may exist but we can't know about them *)
    ; libraries =
        Resolve.return [] (* These may exist but we can't know about them *)
    ; theories_closure =
        lazy (Resolve.return [])
        (* These may exist but we can't know about them *)
    ; package =
        None
        (* For now user-contrib entries will not be associated with a package *)
    }

  let from_coqlib ~coqlib =
    let open Memo.O in
    let* stdlib = stdlib_lib ~coqlib in
    let* subdirs_map =
      let user_contrib =
        Path.append_local coqlib (Path.Local.of_string "user-contrib")
      in
      subdirectory_map Coq_lib_name.empty user_contrib
    in
    let resolve coq_lib_name =
      let looking_for_stdlib =
        Ordering.is_eq
          (Coq_lib_name.compare coq_lib_name (Coq_lib_name.of_string "Coq"))
      in
      match looking_for_stdlib with
      | true -> `Stdlib stdlib
      | false -> (
        Coq_lib_name.Map.find subdirs_map coq_lib_name |> function
        | Some path ->
          `User_contrib (lib_of_user_contrib_name coq_lib_name path)
        | None -> `Not_found)
    in
    Memo.return { parent = None; resolve; boot = None }

  let installed (context : Context.t) =
    let open Memo.O in
    (* First we find coqc so we can query it *)
    Context.which context "coqc" >>= function
    | None ->
      (* If no coqc can be found then we cannot have any installed theories, so
         we return an empty database *)
      Memo.return empty_db
    | Some coqc ->
      (* Next we setup the query for coqc --config *)
      let* coq_config = Coq_config.make ~coqc:(Ok coqc) in
      (* Now we query for coqlib *)
      let coqlib =
        Coq_config.by_name coq_config "coqlib" |> function
        | Some coqlib -> (
          coqlib |> function
          | Coq_config.Value.Path p -> p (* We have found a path for coqlib *)
          | coqlib ->
            (* This should never happen *)
            Code_error.raise "coqlib is not a path"
              [ ("coqlib", Coq_config.Value.to_dyn coqlib) ])
        | None ->
          (* This happens if the output of coqc --config doesn't include coqlib *)
          User_error.raise [ Pp.text "coqlib not found from coqc --config" ]
      in
      from_coqlib ~coqlib
end

let theories_closure t = Lazy.force t.theories_closure
