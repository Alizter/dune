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

module rec R : sig
  type t =
    | Dune of Dune.t
    | Legacy of Legacy.t

  val to_dyn : t -> Dyn.t
end = struct
  type t =
    | Dune of Dune.t
    | Legacy of Legacy.t

  let to_dyn = function
    | Dune t -> Dyn.Variant ("Dune", [ Dune.to_dyn t ])
    | Legacy t -> Dyn.Variant ("Legacy", [ Legacy.to_dyn t ])
end

and Dune : sig
  type t =
    { boot : R.t option Resolve.t
    ; id : Id.t
    ; loc : Loc.t
    ; use_stdlib : bool
    ; src_root : Path.Build.t
    ; obj_root : Path.Build.t
    ; implicit : bool
    ; theories : (Loc.t option * R.t) list Resolve.t
    ; libraries : (Loc.t * Lib.t) list Resolve.t
    ; theories_closure : R.t list Resolve.t Lazy.t
    ; package : Package.t option
    }

  val to_dyn : t -> Dyn.t

  val src_root : t -> Path.Build.t

  val obj_root : t -> Path.Build.t

  val libraries : t -> (Loc.t * Lib.t) list Resolve.t
end = struct
  type t =
    { boot : R.t option Resolve.t
    ; id : Id.t
    ; loc : Loc.t
    ; use_stdlib : bool
    ; src_root : Path.Build.t
    ; obj_root : Path.Build.t
    ; implicit : bool
    ; theories : (Loc.t option * R.t) list Resolve.t
    ; libraries : (Loc.t * Lib.t) list Resolve.t
    ; theories_closure : R.t list Resolve.t Lazy.t
    ; package : Package.t option
    }

  let to_dyn
      { boot
      ; id
      ; loc
      ; use_stdlib
      ; src_root
      ; obj_root
      ; implicit
      ; theories
      ; libraries
      ; theories_closure
      ; package
      } =
    Dyn.record
      [ ("boot", Resolve.to_dyn (Dyn.option R.to_dyn) boot)
      ; ("id", Id.to_dyn id)
      ; ("loc", Loc.to_dyn loc)
      ; ("use_stdlib", Dyn.bool use_stdlib)
      ; ("src_root", Path.Build.to_dyn src_root)
      ; ("obj_root", Path.Build.to_dyn obj_root)
      ; ("implicit", Dyn.bool implicit)
      ; ( "theories"
        , Resolve.to_dyn
            (Dyn.list (Dyn.pair (Dyn.option Loc.to_dyn) R.to_dyn))
            theories )
      ; ( "libraries"
        , Resolve.to_dyn (Dyn.list (Dyn.pair Loc.to_dyn Lib.to_dyn)) libraries
        )
      ; ( "theories_closure"
        , Resolve.to_dyn (Dyn.list R.to_dyn) (Lazy.force theories_closure) )
      ; ("package", Dyn.option Package.to_dyn package)
      ]

  let src_root t = t.src_root

  let obj_root t = t.obj_root

  let libraries t = t.libraries
end

and Legacy : sig
  type t =
    { boot : R.t option Resolve.t
    ; id : Id.t
    ; implicit : bool (* Only useful for the stdlib *)
    ; installed_root : Path.t
    ; libraries_names : string list
    }

  val to_dyn : t -> Dyn.t

  val implicit : t -> bool

  val installed_root : t -> Path.t
end = struct
  type t =
    { boot : R.t option Resolve.t
    ; id : Id.t
    ; implicit : bool (* Only useful for the stdlib *)
    ; installed_root : Path.t
    ; libraries_names : string list
    }

  let to_dyn { boot; id; implicit; installed_root; libraries_names } =
    Dyn.record
      [ ("boot", Resolve.to_dyn (Dyn.option R.to_dyn) boot)
      ; ("id", Id.to_dyn id)
      ; ("implicit", Dyn.bool implicit)
      ; ("installed_root", Path.to_dyn installed_root)
      ; ("libraries_names", Dyn.list Dyn.string libraries_names)
      ]

  let implicit t = t.implicit

  let installed_root t = t.installed_root
end

include R

let boot_of_lib = function
  | Dune t -> t.boot
  | Legacy t -> t.boot

let id_of_lib = function
  | Dune t -> t.id
  | Legacy t -> t.id

let name = function
  | Dune t -> t.id.name
  | Legacy t -> t.id.name

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
  let key t = id_of_lib t in
  let deps t =
    match t with
    | Dune t -> t.theories |> Resolve.map ~f:(List.map ~f:snd)
    | Legacy _ -> Resolve.return []
  in
  fun theories ->
    let open Resolve.O in
    Id.top_closure theories ~key ~deps >>= function
    | Ok s -> Resolve.return s
    | Error _ -> assert false

module DB = struct
  type lib = t

  module Resolve_result = struct
    (** This is the first result of resolving a coq library, later one we will
        refine this data. *)
    type 'a t =
      | Redirect of 'a
      | Theory of Lib.DB.t * Path.Build.t * Coq_stanza.Theory.t
      | Stdlib of lib
      | User_contrib of lib
      | Not_found
  end

  type t =
    { parent : t option
    ; resolve : Coq_lib_name.t -> t Resolve_result.t
    ; boot : (Loc.t * lib Resolve.t Memo.Lazy.t) option
    }

  module Entry = struct
    type nonrec t =
      | Theory of Path.Build.t
      | Redirect of t
  end

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

    let resolve_plugin ~db ~allow_private_deps ~name (loc, lib) =
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
                     "private theory %s may not depend on a public library"
                     (Coq_lib_name.to_string name)
                 ]
      in
      (loc, lib)

    let resolve_plugins ~db ~allow_private_deps ~name plugins =
      let f = resolve_plugin ~db ~allow_private_deps ~name in
      Resolve.Memo.List.map plugins ~f

    let check_boot ~boot ~id (lib : lib) =
      let open Resolve.O in
      let* boot = boot in
      match boot with
      | None -> Resolve.return ()
      | Some boot -> (
        let* boot' = boot_of_lib lib in
        match boot' with
        | None -> Resolve.return ()
        | Some boot' -> (
          match Id.compare (id_of_lib boot) (id_of_lib boot') with
          | Eq -> Resolve.return ()
          | _ -> Error.incompatible_boot (id_of_lib lib) id))

    let maybe_add_boot ~boot ~use_stdlib ~is_boot theories =
      let open Resolve.O in
      let* boot = boot in
      match boot with
      | Some boot when use_stdlib && not is_boot ->
        let+ theories = theories in
        let loc =
          match boot with
          | Dune lib -> Some lib.loc
          | Legacy _ -> None
        in
        (loc, boot) :: theories
      | Some _ | None -> theories

    let resolve_theory ~coq_lang_version ~allow_private_deps ~coq_db ~boot ~id
        (loc, theory_name) =
      let open Resolve.Memo.O in
      let* theory = resolve ~coq_lang_version coq_db (loc, theory_name) in
      let* () = Resolve.Memo.lift @@ check_boot ~boot ~id theory in
      let+ () =
        if allow_private_deps then Resolve.Memo.return ()
        else
          match theory with
          | Dune { package = None; _ } ->
            Error.private_deps_not_allowed ~loc theory_name
          | Legacy _ | Dune _ -> Resolve.Memo.return ()
      in
      (Some loc, theory)

    let resolve_theories ~coq_lang_version ~allow_private_deps ~coq_db ~boot ~id
        theories =
      let f =
        resolve_theory ~coq_lang_version ~allow_private_deps ~coq_db ~boot ~id
      in
      Resolve.Memo.List.map theories ~f

    let create_from_stanza_impl (coq_db, db, dir, (s : Coq_stanza.Theory.t)) =
      let name = snd s.name in
      let id = Id.create ~path:(Path.build dir) ~name in
      let coq_lang_version = s.buildable.coq_lang_version in
      let open Memo.O in
      let* boot = if s.boot then Resolve.Memo.return None else boot coq_db in
      let allow_private_deps = Option.is_none s.package in
      let use_stdlib = s.buildable.use_stdlib in
      let+ libraries =
        resolve_plugins ~db ~allow_private_deps ~name s.buildable.plugins
      and+ theories =
        resolve_theories ~coq_lang_version ~allow_private_deps ~coq_db ~boot ~id
          s.buildable.theories
      in
      let theories =
        maybe_add_boot ~boot ~use_stdlib ~is_boot:s.boot theories
      in
      let map_error x =
        let human_readable_description () = Id.pp id in
        Resolve.push_stack_frame ~human_readable_description x
      in
      let theories = map_error theories in
      let libraries = map_error libraries in
      Dune
        { loc = s.buildable.loc
        ; boot
        ; id
        ; use_stdlib
        ; obj_root = dir
        ; src_root = dir
        ; implicit = s.boot
        ; theories
        ; libraries
        ; theories_closure =
            lazy
              (Resolve.bind theories ~f:(fun theories ->
                   List.map theories ~f:snd |> top_closure))
        ; package = s.package
        }

    module Input = struct
      type nonrec t = t * Lib.DB.t * Path.Build.t * Coq_stanza.Theory.t

      let equal (coq_db, ml_db, path, stanza) (coq_db', ml_db', path', stanza')
          =
        coq_db == coq_db' && ml_db == ml_db'
        && Path.Build.equal path path'
        && stanza == stanza'

      let hash = Poly.hash

      let to_dyn = Dyn.opaque
    end

    let memo =
      Memo.create "create-from-stanza"
        ~human_readable_description:(fun (_, _, path, theory) ->
          Id.pp (Id.create ~path:(Path.build path) ~name:(snd theory.name)))
        ~input:(module Input)
        create_from_stanza_impl

    let create_from_stanza coq_db db dir stanza =
      Memo.exec memo (coq_db, db, dir, stanza)

    module Resolve_result_no_redirect = struct
      (** In our second iteration, we remove all the redirects *)
      type t =
        | Theory of Lib.db * Path.Build.t * Coq_stanza.Theory.t
        | Stdlib of lib
        | User_contrib of lib
        | Not_found
    end

    let rec find coq_db name : Resolve_result_no_redirect.t =
      match coq_db.resolve name with
      | Theory (db, dir, stanza) -> Theory (db, dir, stanza)
      | Redirect coq_db -> find coq_db name
      | Stdlib lib -> Stdlib lib
      | User_contrib lib -> User_contrib lib
      | Not_found -> (
        match coq_db.parent with
        | None -> Not_found
        | Some parent -> find parent name)

    module Resolve_final_result = struct
      (** Next we find corresponding Coq libraries for the various cases *)
      type t =
        | Found_lib of lib
        | Found_stanza of Lib.DB.t * Path.Build.t * Coq_stanza.Theory.t
        | Hidden
        | Not_found
    end

    let find coq_db ~coq_lang_version name : Resolve_final_result.t =
      match find coq_db name with
      | Not_found -> Not_found
      (* Composing with installed theories should come past 0.8 *)
      | (Stdlib lib | User_contrib lib) when coq_lang_version >= (0, 8) ->
        Found_lib lib
      | Stdlib _ | User_contrib _ -> Not_found
      (* Composing with theories in the same project should come past 0.4 *)
      | Theory (mldb, dir, stanza) when coq_lang_version >= (0, 4) ->
        Found_stanza (mldb, dir, stanza)
      | Theory (mldb, dir, stanza) -> (
        match coq_db.resolve name with
        | Not_found -> Hidden
        | Theory _ | Redirect _ | Stdlib _ | User_contrib _ ->
          Found_stanza (mldb, dir, stanza))

    (** Our final final resolve is used externally, and should return the
        library data found from the previous iterations. *)
    let resolve coq_db ~coq_lang_version (loc, name) =
      match find coq_db ~coq_lang_version name with
      | Not_found -> Error.theory_not_found ~loc name
      | Hidden -> Error.hidden_without_composition ~loc name
      | Found_stanza (db, dir, stanza) ->
        let open Memo.O in
        let+ theory = create_from_stanza coq_db db dir stanza in
        let open Resolve.O in
        let* (_ : (Loc.t * Lib.t) list) =
          match theory with
          | Dune t -> t.libraries
          | Legacy _ -> Resolve.return []
        in
        let+ (_ : (Loc.t option * lib) list) =
          match theory with
          | Dune t -> t.theories
          | Legacy _ -> Resolve.return []
        in
        theory
      | Found_lib lib -> Resolve.Memo.return lib
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
      (entries : (Coq_stanza.Theory.t * Entry.t) list) =
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
    let resolve name =
      match Coq_lib_name.Map.find map name with
      | None -> Resolve_result.Not_found
      | Some (theory, entry) -> (
        match entry with
        | Theory dir -> Theory (find_db dir, dir, theory)
        | Redirect db -> Redirect db)
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
    let resolve _ = Resolve_result.Not_found in
    { parent = None; resolve; boot = None }

  (* TODO: merge with below *)
  let stdlib_lib ~coqlib =
    let theories_dir =
      Path.append_local coqlib (Path.Local.of_string "theories")
    in
    Memo.return
    @@ Legacy
         { boot = Resolve.return None (* TODO needs fixing *)
         ; id = Id.create ~path:theories_dir ~name:Coq_lib_name.stdlib
         ; implicit = true (* TODO do we want to keep implicit for now? *)
         ; installed_root = theories_dir
         ; libraries_names = [] (* TODO fix *)
         }

  let lib_of_user_contrib_name ~stdlib name path : lib =
    Legacy
      { boot = Resolve.return (Some stdlib)
      ; id = Id.create ~name ~path
      ; implicit = false
      ; installed_root = path
      ; libraries_names = [] (* TODO fix *)
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
              | Unix.S_DIR ->
                (* We cannot just accept any directory, so we need to validate
                   the name. This validation is not complete, but it is good
                   enough. *)
                if String.contains file '.' then None
                else if String.contains file '-' then None
                else Some file
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
    | Error _ ->
      Memo.return Coq_lib_name.Map.empty
      (* User_error.raise
         [ Pp.text "System error encountered when finding coqlib:"
         ; Unix_error.Detailed.pp x
         ] *)
    | _ ->
      Code_error.raise "subdirectory_map: dir does not exist"
        [ ("name", Coq_lib_name.to_dyn name); ("dir", Path.to_dyn dir) ]

  let installed_libs_map ~coqlib ~coqpath =
    (* We create a map of libnames to paths for the installed libraries. This
       map includes user-contrib, any paths in COQPATH but not the standard
       library. For now. *)
    let open Memo.O in
    let user_contrib_path =
      Path.append_local coqlib (Path.Local.of_string "user-contrib")
    in
    let coqpath = user_contrib_path :: coqpath in
    let+ subdir_maps =
      Memo.all @@ List.map coqpath ~f:(subdirectory_map Coq_lib_name.empty)
    in
    Coq_lib_name.Map.union_exn
      (List.fold_left subdir_maps
         ~init:Coq_lib_name.Map.empty
           (* TODO need better handling in this union. We cannot use union_exn
              here as we are handling the empty lib name which we don't care about.
              However if there are multiple directories corresponding to a libname,
              we have to pick one of them. *)
         ~f:
           (Coq_lib_name.Map.union ~f:(fun lib_name x y ->
                match Coq_lib_name.equal lib_name Coq_lib_name.empty with
                | false ->
                  User_error.raise
                    [ Pp.textf "The Coq theory name %S corresponds to both:"
                        (Coq_lib_name.to_string lib_name)
                    ; Pp.enumerate [ x; y ] ~f:Path.pp
                    ; Pp.text
                        "Coq theory names must correspond to a unique \
                         directory."
                    ]
                | true -> Some x)))
      (Coq_lib_name.Map.singleton Coq_lib_name.stdlib coqlib)

  let from_coqlib ~coqlib ~coqpath =
    (* TODO handling of stdlib and other libs should be more uniform *)
    let open Memo.O in
    let* stdlib = stdlib_lib ~coqlib in
    let* subdirs_map = installed_libs_map ~coqlib ~coqpath in
    let resolve coq_lib_name =
      (* First we check if we are trying to find the stdlib *)
      match Coq_lib_name.equal coq_lib_name Coq_lib_name.stdlib with
      | true -> Resolve_result.Stdlib stdlib
      | false -> (
        Coq_lib_name.Map.find subdirs_map coq_lib_name |> function
        | Some path ->
          Resolve_result.User_contrib
            (lib_of_user_contrib_name ~stdlib coq_lib_name path)
        | None -> Resolve_result.Not_found)
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
      let coqpath =
        (* windows uses ';' *)
        let coqpath_sep = if Sys.cygwin then ';' else Bin.path_sep in
        Env.get context.env "COQPATH" |> function
        | None -> []
        | Some coqpath -> Bin.parse_path ~sep:coqpath_sep coqpath
      in
      from_coqlib ~coqlib ~coqpath
end

let theories_closure t =
  match t with
  | Dune t -> Lazy.force t.theories_closure
  | Legacy _ -> Resolve.return []
