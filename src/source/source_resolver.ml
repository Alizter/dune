open Import

(* Unique tags per resolver, so callers can compare resolvers reliably
   (e.g. to gate workspace-only behaviour) without depending on physical
   equality of closures. *)
module Id = Id.Make ()

(* A resolver tells callers how to read bytes for a [Path.Source.t]:

   - [resolve] returns the physical [Path.Outside_build_dir.t] when
     one exists. Filesystem and external-mount backings supply a real
     mapping; vcs and build-dir backings can't represent bytes as a
     filesystem path and return a vestigial [In_source_dir p] (callers
     that need a real path on those backings must go through other
     APIs such as [Source_tree.Dir.file_source]).

   - [file_exists] / [with_lexbuf_from_file] are the read mechanism
     used by [(include ...)] resolution. Filesystem backings route
     through [Fs_memo]; vcs and build-dir backings route through
     their own bytes (so includes resolve against the backing's
     actual sources rather than the workspace root). *)
(* Wrapper for the polymorphic [with_lexbuf_from_file] closure: a
   plain function argument can't be assigned to a record field with
   universal polymorphism, so callers pass [{ f }] explicitly. *)
type with_lexbuf =
  { f : 'a. Path.Source.t -> f:(Lexing.lexbuf -> 'a) -> 'a Memo.t }

type t =
  { id : Id.t
  ; resolve : Path.Source.t -> Path.Outside_build_dir.t
  ; file_exists : Path.Source.t -> bool Memo.t
  ; with_lexbuf_from_file : with_lexbuf
  }

let workspace =
  { id = Id.gen ()
  ; resolve = (fun p -> Path.Outside_build_dir.In_source_dir p)
  ; file_exists = (fun p -> Fs_memo.file_exists (In_source_dir p))
  ; with_lexbuf_from_file =
      { f = (fun p ~f -> Fs_memo.with_lexbuf_from_file (In_source_dir p) ~f) }
  }
;;

let create_fs resolve =
  { id = Id.gen ()
  ; resolve
  ; file_exists = (fun p -> Fs_memo.file_exists (resolve p))
  ; with_lexbuf_from_file =
      { f = (fun p ~f -> Fs_memo.with_lexbuf_from_file (resolve p) ~f) }
  }
;;

let create_custom ~resolve ~file_exists ~with_lexbuf_from_file =
  { id = Id.gen (); resolve; file_exists; with_lexbuf_from_file }
;;

let resolve t = t.resolve
let file_exists t = t.file_exists
let with_lexbuf_from_file t p ~f = t.with_lexbuf_from_file.f p ~f
let equal a b = Id.equal a.id b.id
let is_workspace t = equal t workspace
