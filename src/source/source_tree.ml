open Import
open Memo.O

module Dirs_visited : sig
  (** Unique set of all directories visited *)
  type t

  val singleton : Path.Source.t -> Dir_contents.File.t -> t
  val empty : t
  val add : t -> Path.Source.t -> Dir_contents.File.t -> t
end = struct
  type t = Path.Source.t Dir_contents.File.Map.t

  let empty = Dir_contents.File.Map.empty
  let singleton path file = Dir_contents.File.Map.singleton file path

  let add (t : t) (path : Path.Source.t) file =
    if Sys.win32
    then t
    else
      Dir_contents.File.Map.update t file ~f:(function
        | None -> Some path
        | Some first_path ->
          User_error.raise
            [ Pp.textf
                "Path %s has already been scanned. Cannot scan it again through symlink \
                 %s"
                (Path.Source.to_string_maybe_quoted first_path)
                (Path.Source.to_string_maybe_quoted path)
            ])
  ;;
end

(* Per-tree closures controlling how the source tree's bytes and
   directory structure are read. Filesystem-backed trees route reads
   through Fs_memo + the resolver; vcs-backed trees pull bytes and
   listings from a [Vcs_tree.t] directly without touching the
   filesystem. *)
type backing =
  { resolver : Source_resolver.t
  ; byte_provider : Path.Source.t -> string Memo.t
  ; readdir : Path.Source.t -> Dir_contents.t Memo.t
  ; file_identity : Path.Source.t -> Dir_contents.File.t Memo.t
  ; vcs_tree : Dune_vcs.Vcs_tree.t option
  }

module Dir0 = struct
  module Vcs = struct
    type nonrec t =
      | This of Vcs.t
      | Ancestor_vcs

    let get_vcs ~default:vcs ~readdir ~path =
      match
        Vcs.Kind.of_dir_contents
          ~files:(Dir_contents.files readdir)
          ~dirs:(Dir_contents.dirs readdir)
      with
      | None -> vcs
      | Some kind -> This { Vcs.kind; root = Path.(append_source root) path }
    ;;
  end

  type t =
    { path : Path.Source.t
    ; status : Source_dir_status.t
    ; files : Filename.Array.Set.t
    ; sub_dirs : sub_dir Filename.Array.Map.t
    ; dune_file : Dune_file.t option
    ; project : Dune_project.t
    ; vcs : Vcs.t
    ; backing : backing
    }

  and sub_dir =
    { sub_dir_status : Source_dir_status.t
    ; sub_dir_as_t : t Memo.t
    }

  let rec to_dyn
            { path
            ; status
            ; files
            ; dune_file
            ; sub_dirs
            ; vcs = _
            ; project = _
            ; backing = _
            }
    =
    Dyn.record
      [ "path", Path.Source.to_dyn path
      ; "status", Source_dir_status.to_dyn status
      ; "files", Dyn.Set (Filename.Array.Set.to_list_map files ~f:Filename.to_dyn)
      ; ( "sub_dirs"
        , Dyn.Map
            (Filename.Array.Map.to_list_map sub_dirs ~f:(fun name sub_dir ->
               Filename.to_dyn name, dyn_of_sub_dir sub_dir)) )
      ; ("dune_file", Dyn.(option opaque dune_file))
      ]

  and dyn_of_sub_dir { sub_dir_status; sub_dir_as_t = _ } =
    Dyn.record [ "status", Source_dir_status.to_dyn sub_dir_status ]
  ;;

  let path t = t.path
  let status t = t.status
  let filenames t = t.files
  let sub_dirs t = t.sub_dirs
  let dune_file t = t.dune_file
  let project t = t.project
  let sub_dir_names t = Filename.Array.Map.keys t.sub_dirs
  let sub_dir_as_t (s : sub_dir) = s.sub_dir_as_t

  let file_path t filename =
    match t.backing.vcs_tree with
    | Some _ ->
      Code_error.raise
        "Source_tree.Dir.file_path called on a vcs-backed directory; callers must use \
         file_source instead."
        [ "path", Path.Source.to_dyn t.path; "filename", Filename.to_dyn filename ]
    | None ->
      let logical = Path.Source.relative_fname t.path filename in
      Source_resolver.resolve t.backing.resolver logical
  ;;

  let file_source t filename : Dune_engine.Build_config.source_file =
    let logical = Path.Source.relative_fname t.path filename in
    match t.backing.vcs_tree with
    | Some vcs_tree -> Vcs_blob (Dune_vcs.Vcs_tree.read_file vcs_tree logical)
    | None -> Filesystem (Source_resolver.resolve t.backing.resolver logical)
  ;;
end

let eval_status ~status_map ~(parent_status : Source_dir_status.t) dir
  : Source_dir_status.t option
  =
  match Source_dir_status.Per_dir.status status_map ~dir with
  | Ignored -> None
  | Status status ->
    Some
      (match parent_status, status with
       | Data_only, _ -> Data_only
       | Vendored, Normal -> Vendored
       | _, _ -> status)
;;

let error_unable_to_load ~path unix_error =
  User_error.raise
    [ Pp.textf "Unable to load source %s." (Path.Source.to_string_maybe_quoted path)
    ; Unix_error.Detailed.pp_reason unix_error
    ]
;;

let rec physical
          ~backing
          ~project
          ~default_vcs
          ~dir
          ~dirs_visited
          ~dirs
          ~sub_dirs
          ~dune_file
          ~parent_status
  =
  let status_map =
    Source_dir_status.Spec.eval sub_dirs ~dirs:(Filename.Array.Map.keys dirs)
  in
  Filename.Array.Map.filter_mapi dirs ~f:(fun fn file ->
    match eval_status ~status_map ~parent_status fn with
    | None -> None
    | Some dir_status ->
      let path = Path.Source.relative_fname dir fn in
      let dirs_visited = Dirs_visited.add dirs_visited path file in
      Some
        { Dir0.sub_dir_status = dir_status
        ; sub_dir_as_t =
            Memo.lazy_node (fun () ->
              find_dir_raw
                ~backing
                ~default_vcs
                ~path
                ~basename:fn
                ~virtual_:false
                ~dirs_visited
                ~dune_file
                ~status:dir_status
                ~project)
            |> Memo.Node.read
        })

and virtual_ ~backing ~project ~sub_dirs ~parent_status ~dune_file ~init ~path =
  match dune_file with
  | None -> init
  | Some df ->
    (* There's no files to read for virtual directories, but we still record
       their entries *)
    let dirs = Dune_file.sub_dirnames df in
    let status_map = Source_dir_status.Spec.eval sub_dirs ~dirs in
    let virtual_dirs =
      Filename.Array.Set.to_list_map dirs ~f:(fun fn ->
        match eval_status ~status_map ~parent_status fn with
        | None -> None
        | Some status ->
          if Filename.Array.Map.mem init fn
          then None
          else
            Some
              ( fn
              , { Dir0.sub_dir_status = status
                ; sub_dir_as_t =
                    Memo.lazy_node (fun () ->
                      find_dir_raw
                        ~backing
                        ~default_vcs:Dir0.Vcs.Ancestor_vcs
                        ~path:(Path.Source.relative_fname path fn)
                        ~basename:fn
                        ~virtual_:true
                        ~dune_file
                        ~status
                        ~dirs_visited:Dirs_visited.empty
                        ~project)
                    |> Memo.Node.read
                } ))
      |> List.filter_opt
      |> Filename.Array.Map.of_sorted_list_exn
    in
    Filename.Array.Map.union_left_biased init virtual_dirs

and contents
      ~backing
      readdir
      ~default_vcs
      ~path
      ~dune_file
      ~dirs_visited
      ~project
      ~(dir_status : Source_dir_status.t)
  =
  let files = Dir_contents.files readdir in
  let+ dune_file =
    Dune_file.load
      ~resolver:backing.resolver
      ~byte_provider:backing.byte_provider
      ~dir:path
      dir_status
      project
      ~files
      ~parent:dune_file
  in
  let files =
    let predicate =
      match dune_file with
      | None -> Dune_file.Files.default
      | Some dune_file -> Dune_file.files dune_file
    in
    Dune_file.Files.eval predicate ~files
  in
  let vcs = Dir0.Vcs.get_vcs ~default:default_vcs ~readdir ~path in
  let sub_dirs =
    let sub_dirs =
      match dune_file with
      | None -> Source_dir_status.Spec.default
      | Some dune_file -> Dune_file.sub_dir_status dune_file
    in
    let dirs =
      physical
        ~backing
        ~default_vcs:vcs
        ~project
        ~dir:path
        ~dirs_visited
        ~dirs:(Dir_contents.dirs readdir)
        ~sub_dirs
        ~dune_file
        ~parent_status:dir_status
    in
    virtual_
      ~backing
      ~project
      ~sub_dirs
      ~parent_status:dir_status
      ~dune_file
      ~path
      ~init:dirs
  in
  { Dir0.project; vcs; status = dir_status; path; files; sub_dirs; dune_file; backing }

and find_dir_raw
      ~backing
      ~virtual_
      ~default_vcs
      ~dune_file
      ~status
      ~dirs_visited
      ~project
      ~path
      ~basename
  : Dir0.t Memo.t
  =
  let status =
    if Dune_project.cram project && Cram_test.is_cram_suffix basename
    then Source_dir_status.Data_only
    else status
  in
  let* readdir =
    if virtual_ then Memo.return Dir_contents.empty else backing.readdir path
  in
  let* project =
    if status = Data_only
    then Memo.return project
    else
      Dune_project.gen_load
        ~read:backing.byte_provider
        ~dir:path
        ~files:(Dir_contents.files readdir)
        ~infer_from_opam_files:false
        ~load_opam_file_with_contents:Dune_pkg.Opam_file.load_opam_file_with_contents
      >>| Option.map
            ~f:(Only_packages.filter_packages_in_project ~vendored:(status = Vendored))
      >>| Option.value ~default:project
  in
  contents
    ~backing
    readdir
    ~default_vcs
    ~path
    ~dune_file
    ~dirs_visited
    ~project
    ~dir_status:status
;;

let make_root_node ~backing ~read_only ~vendored =
  Memo.lazy_node
  @@ fun () ->
  let path = Path.Source.root in
  (* [vendored] is set by callers that intend the tree to be treated
     as third-party (fetched dependencies, vendored mounts): warnings
     are suppressed and packages are filtered as if listed in
     [(vendored_dirs ...)]. It's independent of [read_only] (which
     only controls promotion). A vcs revision is read-only but not
     vendored — it's the user's own code at a specific point in
     time. *)
  let _ = read_only in
  let dir_status : Source_dir_status.t = if vendored then Vendored else Normal in
  let* readdir = backing.readdir path in
  let vcs = Dir0.Vcs.get_vcs ~default:Ancestor_vcs ~readdir ~path in
  let* project =
    Dune_project.gen_load
      ~read:backing.byte_provider
      ~dir:path
      ~files:(Dir_contents.files readdir)
      ~infer_from_opam_files:true
      ~load_opam_file_with_contents:Dune_pkg.Opam_file.load_opam_file_with_contents
    >>| (function
     | Some p -> p
     | None -> Dune_project.anonymous ~dir:path Package_info.empty Package.Name.Map.empty)
    >>| Only_packages.filter_packages_in_project ~vendored:(dir_status = Vendored)
  in
  let* file = backing.file_identity path in
  let dirs_visited = Dirs_visited.singleton path file in
  contents
    ~backing
    readdir
    ~default_vcs:vcs
    ~path
    ~dune_file:None
    ~dirs_visited
    ~project
    ~dir_status
;;

type t =
  { root_node : (unit, Dir0.t) Memo.Node.t
  ; read_only : bool
  }

(* Filesystem backing: every closure delegates to Fs_memo + the
   resolver. This is the existing pre-vcs behaviour, factored out so
   vcs-backed trees can supply a different backing. *)
let filesystem_backing resolver =
  let resolve = Source_resolver.resolve resolver in
  let byte_provider source = Dune_engine.Fs_memo.file_contents (resolve source) in
  let readdir path =
    Dir_contents.of_outside_build_dir ~path_for_hint:path ~physical:(resolve path)
    >>| function
    | Ok dir -> dir
    | Error _ -> Dir_contents.empty
  in
  let file_identity path =
    Dir_contents.File.of_path (resolve path)
    >>| function
    | Ok file -> file
    | Error unix_error -> error_unable_to_load ~path unix_error
  in
  { resolver; byte_provider; readdir; file_identity; vcs_tree = None }
;;

(* Vcs backing: directory listings come from the in-memory tree,
   bytes come from [Vcs_tree.read_file] (which shells out to the
   backend); no filesystem reads happen at any point. *)
let vcs_backing vcs_tree =
  let byte_provider source = Dune_vcs.Vcs_tree.read_file vcs_tree source in
  (* Each directory in the vcs tree gets a synthetic [File.t] derived
     from its path, so [Dirs_visited]'s symlink-loop check (which keys
     directories by their inode) doesn't see false-positive collisions. *)
  let dir_identity path = Dir_contents.File.synthetic (Path.Source.to_string path) in
  let readdir path =
    let+ entries =
      Memo.of_non_reproducible_fiber (Dune_vcs.Vcs_tree.list_dir vcs_tree path)
    in
    let files, dirs =
      List.partition_map entries ~f:(function
        | `File fn -> Left fn
        | `Dir fn -> Right (fn, dir_identity (Path.Source.relative_fname path fn)))
    in
    let dirs =
      List.sort dirs ~compare:(fun (a, _) (b, _) -> Filename.compare a b)
      |> Filename.Array.Map.of_sorted_list_exn
    in
    let files =
      List.sort files ~compare:Filename.compare |> Filename.Array.Set.of_sorted_list
    in
    Dir_contents.make ~files ~dirs
  in
  let file_identity path = Memo.return (dir_identity path) in
  (* The resolver is kept around to satisfy callers that branch on
     [Source_resolver.is_workspace] (notably the missing-dune-project
     warning), but [file_path] errors before consulting it. *)
  let resolver =
    Source_resolver.create (fun p -> Path.Outside_build_dir.In_source_dir p)
  in
  { resolver; byte_provider; readdir; file_identity; vcs_tree = Some vcs_tree }
;;

let default =
  { root_node =
      make_root_node
        ~backing:(filesystem_backing Source_resolver.workspace)
        ~read_only:false
        ~vendored:false
  ; read_only = false
  }
;;

let of_external_root ?(read_only = true) root =
  let resolver =
    Source_resolver.create (fun p ->
      if Path.Source.is_root p
      then Path.Outside_build_dir.External root
      else
        Path.Outside_build_dir.External
          (Path.External.relative root (Path.Source.to_string p)))
  in
  (* External roots default to read-only-and-vendored; this is the
     classic "fetched dependency" mode used by [dune pkg] and
     vendored mounts. *)
  { root_node =
      make_root_node ~backing:(filesystem_backing resolver) ~read_only ~vendored:read_only
  ; read_only
  }
;;

let of_vcs_tree vcs_tree =
  (* A vcs revision is read-only (no promotion) but NOT vendored: it's
     the user's own code at a specific point in time, and we want
     dune to generate rules, run @runtest, etc. against it normally. *)
  { root_node =
      make_root_node ~backing:(vcs_backing vcs_tree) ~read_only:true ~vendored:false
  ; read_only = true
  }
;;

(* Build-dir backing: bytes and listings come from a [Path.Build.t]
   root via the [Build_system]. Each read forces the producing rule
   first, so source-tree reads are correctly ordered against the
   action graph — the same pattern [(dynamic_include ...)] uses to
   read dune-files emitted by actions (see
   [src/source/include_stanza.ml]). Used by pkg mounts where the
   pkg's source dir is the directory target of a Fetch / copy
   action. *)
let build_dir_backing (root : Path.Build.t) =
  let physical_of source =
    if Path.Source.is_root source
    then Path.build root
    else Path.build (Path.Build.append_source root source)
  in
  let byte_provider source = Build_system.read_file (physical_of source) in
  let dir_identity path =
    Dir_contents.File.synthetic ("build:" ^ Path.Source.to_string path)
  in
  let readdir path =
    (* Just untracked readdir: returns empty when the dir doesn't yet
       exist. The producing action runs separately via the regular
       rule pipeline; this read picks up whatever is currently on
       disk. *)
    let dir = physical_of path in
    match Path.Untracked.readdir_unsorted_with_kinds dir with
    | Error _ -> Memo.return Dir_contents.empty
    | Ok entries ->
      let files, dirs =
        List.partition_map entries ~f:(fun (fn, (kind : Unix.file_kind)) ->
          match kind with
          | S_DIR -> Right (fn, dir_identity (Path.Source.relative_fname path fn))
          | _ -> Left fn)
      in
      let dirs =
        List.sort dirs ~compare:(fun (a, _) (b, _) -> Filename.compare a b)
        |> Filename.Array.Map.of_sorted_list_exn
      in
      let files =
        List.sort files ~compare:Filename.compare |> Filename.Array.Set.of_sorted_list
      in
      Memo.return (Dir_contents.make ~files ~dirs)
  in
  let file_identity path = Memo.return (dir_identity path) in
  (* Vestigial resolver — kept so callers branching on
     [Source_resolver.is_workspace] (e.g. the missing-dune-project
     warning) behave consistently. Actual reads go through
     [byte_provider] / [readdir]. *)
  let resolver =
    Source_resolver.create (fun p -> Path.Outside_build_dir.In_source_dir p)
  in
  { resolver; byte_provider; readdir; file_identity; vcs_tree = None }
;;

let of_build_dir root =
  (* Bytes are produced by an action; treat the tree as read-only and
     vendored (no promotion, no parse-warning emission). *)
  { root_node =
      make_root_node ~backing:(build_dir_backing root) ~read_only:true ~vendored:true
  ; read_only = true
  }
;;

let read_only t = t.read_only
let root t = Memo.Node.read t.root_node
let for_context_callback : (Context_name.t -> t Memo.t) Fdecl.t = Fdecl.create Dyn.opaque
let set_for_context_callback f = Fdecl.set for_context_callback f
let for_context ctx = (Fdecl.get for_context_callback) ctx

let gen_find_dir =
  let rec loop on_success on_last_found components (dir : Dir0.t) =
    match components with
    | [] -> on_success dir
    | x :: xs ->
      (match Filename.Array.Map.find dir.sub_dirs x with
       | None -> on_last_found dir
       | Some dir -> dir.sub_dir_as_t >>= loop on_success on_last_found xs)
  in
  fun ~on_success ~on_last_found t p ->
    Memo.Node.read t.root_node >>= loop on_success on_last_found (Path.Source.explode p)
;;

let find_dir =
  gen_find_dir
    ~on_success:(fun dir -> Memo.return (Some dir))
    ~on_last_found:(fun _ -> Memo.return None)
;;

let nearest_dir = gen_find_dir ~on_success:Memo.return ~on_last_found:Memo.return

let find_excluded_ancestor t path =
  let rec loop (dir : Dir0.t) = function
    | [] -> Memo.return None
    | sub_dir :: path ->
      (match Filename.Array.Map.find dir.sub_dirs sub_dir with
       | Some sub_dir ->
         let* child = sub_dir.sub_dir_as_t in
         loop child path
       | None ->
         Dir_contents.of_source_path dir.path
         >>| (function
          | Ok contents when Filename.Array.Map.mem (Dir_contents.dirs contents) sub_dir
            ->
            dir.dune_file
            |> Option.bind ~f:Dune_file.dirs_stanza_loc
            |> Option.map ~f:(fun loc -> Path.Source.relative_fname dir.path sub_dir, loc)
          | _ -> None))
  in
  let* root = Memo.Node.read t.root_node in
  loop root (Path.Source.explode path)
;;

let files_of t path =
  find_dir t path
  >>| function
  | None -> Path.Source.Set.empty
  | Some dir ->
    Dir0.filenames dir
    |> Filename.Array.Set.to_list
    |> Path.Source.Set.of_list_map ~f:(Path.Source.relative_fname path)
;;

let file_exists t path =
  match Path.Source.parent path with
  | None -> Memo.return false
  | Some parent ->
    find_dir t parent
    >>| (function
     | None -> false
     | Some dir -> Filename.Array.Set.mem (Dir0.filenames dir) (Path.Source.basename path))
;;

module Dir = struct
  include Dir0

  module Make_map_reduce (M : Memo.S) (Outcome : Monoid) = struct
    open M.O

    let map_reduce =
      let rec map_reduce t ~traverse ~trace_event_name ~f =
        let must_traverse = Source_dir_status.Map.find traverse t.status in
        match must_traverse with
        | false -> M.return Outcome.empty
        | true ->
          let+ here = f t
          and+ in_sub_dirs =
            M.List.map
              (Filename.Array.Map.to_list_map t.sub_dirs ~f:(fun _ s -> s))
              ~f:(fun s ->
                let* t = M.of_memo (sub_dir_as_t s) in
                map_reduce t ~traverse ~trace_event_name ~f)
          in
          List.fold_left in_sub_dirs ~init:here ~f:Outcome.combine
      in
      let impl =
        lazy
          (match Dune_trace.global () with
           | None -> map_reduce
           | Some trace ->
             fun t ~traverse ~trace_event_name ~f ->
               let start = Time.now () in
               let+ res = map_reduce t ~traverse ~trace_event_name ~f in
               let stop = Time.now () in
               let event =
                 Dune_trace.Event.scan_source
                   ~name:trace_event_name
                   ~start
                   ~stop
                   ~dir:t.path
               in
               Dune_trace.Out.emit trace event;
               res)
      in
      fun t ~traverse ~trace_event_name ~f ->
        (Lazy.force impl) t ~traverse ~trace_event_name ~f
    ;;
  end
end

module Make_map_reduce_with_progress (M : Memo.S) (Outcome : Monoid) = struct
  open M.O
  include Dir.Make_map_reduce (M) (Outcome)

  let map_reduce t ~traverse ~trace_event_name ~f =
    let* root = M.of_memo (root t) in
    let nb_path_visited = ref 0 in
    let overlay =
      Console.Status_line.add_overlay
        (Live (fun () -> Pp.textf "Scanned %i directories" !nb_path_visited))
    in
    let+ res =
      map_reduce root ~traverse ~trace_event_name ~f:(fun dir ->
        incr nb_path_visited;
        if !nb_path_visited mod 100 = 0 then Console.Status_line.refresh ();
        f dir)
    in
    Console.Status_line.remove_overlay overlay;
    res
  ;;
end

let is_vendored t dir =
  find_dir t dir
  >>| function
  | None -> false
  | Some d -> Dir.status d = Vendored
;;

let ancestor_vcs =
  Memo.lazy_ ~name:"ancestor_vcs" (fun () ->
    if Execution_env.inside_dune
    then Memo.return None
    else (
      let rec loop dir =
        if Fpath.is_root dir
        then None
        else (
          let dir = Filename.dirname dir in
          match
            let files =
              Sys.readdir dir
              |> Stdlib.Array.to_list
              |> List.map ~f:Filename.of_string_exn
              |> Filename.Array.Set.of_list
            in
            Vcs.Kind.of_dir_contents ~files ~dirs:Filename.Array.Map.empty
          with
          | Some kind -> Some { Vcs.kind; root = Path.of_string dir }
          | None -> loop dir
          | exception Sys_error msg ->
            User_warning.emit
              [ Pp.textf
                  "Unable to read directory %s. Will not look for VCS root in parent \
                   directories."
                  dir
              ; User_error.reason (Pp.verbatim msg)
              ];
            None)
      in
      Memo.return (loop (Path.to_absolute_filename Path.root))))
;;

let nearest_vcs t dir =
  let* dir = nearest_dir t dir in
  match dir.vcs with
  | This vcs -> Memo.return (Some vcs)
  | Ancestor_vcs -> Memo.Lazy.force ancestor_vcs
;;
