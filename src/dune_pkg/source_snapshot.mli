open Import

module Archive : sig
  type t =
    { path : Path.t
    ; filename : Filename.t
    ; digest : Dune_digest.t
    }
end

type t

val prepare : Archive.t -> t Memo.t
val id : t -> Dune_digest.t
val manifest_digest : t -> Dune_digest.t
val readdir : t -> Path.Local.t -> [ `Dir | `File ] Filename.Map.t Memo.t
val read_file : t -> Path.Local.t -> string Memo.t
val file_path : t -> Path.Local.t -> Path.t
