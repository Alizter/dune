open Import

type opam =
  { stanza : Opam_stanza.t
  ; paths : Path.Build.t Package_deps.Paths.t
  }

type t

type any_package =
  | Local of Package.t
  | Installed of Dune_package.t
  | Opam of opam

val create : Context_name.t -> t Memo.t
val user_opam_packages : t -> opam Package.Name.Map.t
val find_package : t -> Package.Name.t -> any_package option Memo.t

val section_of_any_package_site
  :  any_package
  -> Package.Name.t
  -> Loc.t
  -> Site.t
  -> Dune_section.t

val section_of_site
  :  t
  -> loc:Loc.t
  -> pkg:Package.Name.t
  -> site:Site.t
  -> Section.t Memo.t
