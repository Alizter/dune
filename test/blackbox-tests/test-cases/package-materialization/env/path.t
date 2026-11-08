Test that (deps (package ...)) adds the package's bin/ to PATH.

  $ make_dune_project_with_package 3.24 mypkg
  $ mkdir src
  $ cat >src/dune <<EOF
  > (executable (name mytool) (public_name mytool) (package mypkg) (modules mytool))
  > (library (public_name mypkg) (modules mypkg))
  > EOF
  $ cat >src/mytool.ml <<'EOF'
  > let () = print_endline "hello"
  > EOF
  $ cat >src/mypkg.ml <<'EOF'
  > let x = 1
  > EOF
  $ cat >dune <<'EOF'
  > (rule
  >  (deps (package mypkg))
  >  (action (with-stdout-to out (bash "echo $PATH"))))
  > EOF

  $ baseline=$PATH
  $ dune build out
  $ env_added "$(cat _build/default/out)" "$baseline" | censor
  $PWD/_build/.sandbox/$DIGEST1/install/default/.packages/$DIGEST2/bin

All install-managed variables must refer to sandbox copies, not to undeclared
files left in a previously materialised layout. The same holds for action-local
overrides of these variables.

  $ cat >> dune <<'EOF'
  > (executable (name probe) (modules probe))
  > (rule
  >  (target initial)
  >  (deps (sandbox always) (package mypkg))
  >  (action (with-stdout-to %{target} (run ./probe.exe))))
  > EOF
  $ cat > probe.ml <<'EOF'
  > let variables =
  >   [ "PATH"; "OCAMLPATH"; "CAML_LD_LIBRARY_PATH";
  >     "OCAMLTOP_INCLUDE_PATH"; "MANPATH"; "OCAMLFIND_IGNORE_DUPS_IN" ]
  > 
  > let normalize = String.map (function '\\' -> '/' | c -> c)
  > 
  > let () =
  >   let prefix =
  >     Filename.concat (Filename.dirname (Sys.getcwd ())) "install"
  >     |> normalize
  >   in
  >   List.iter (fun var ->
  >     let sep =
  >       if Sys.win32 || (Sys.cygwin &&
  >         (var = "OCAMLPATH" || var = "OCAMLFIND_IGNORE_DUPS_IN"))
  >       then ';' else ':'
  >     in
  >     let dir = List.hd (String.split_on_char sep (Sys.getenv var)) in
  >     let leaked = Sys.file_exists (Filename.concat dir "undeclared") in
  >     let dir = normalize dir in
  >     let sandboxed = String.length dir >= String.length prefix &&
  >       String.sub dir 0 (String.length prefix) = prefix in
  >     Printf.printf "%s: %s, %s\n" var
  >       (if sandboxed then "sandbox" else "real")
  >       (if leaked then "leaked" else "isolated")
  >   ) variables
  > EOF
  $ dune build probe.exe
  $ for layout in _build/install/default/.packages/*; do
  >   for dir in bin lib lib/stublibs lib/toplevel man; do
  >     mkdir -p "$layout/$dir"
  >     echo leaked > "$layout/$dir/undeclared"
  >   done
  > done
  $ dune build initial --sandbox copy
  $ cat _build/default/initial
  PATH: sandbox, isolated
  OCAMLPATH: sandbox, isolated
  CAML_LD_LIBRARY_PATH: sandbox, isolated
  OCAMLTOP_INCLUDE_PATH: sandbox, isolated
  MANPATH: sandbox, isolated
  OCAMLFIND_IGNORE_DUPS_IN: sandbox, isolated

  $ layout="$PWD/$(echo _build/install/default/.packages/*)"
  $ cat >> dune <<EOF
  > (rule
  >  (target override)
  >  (deps (sandbox always) (package mypkg))
  >  (action
  >   (with-stdout-to %{target}
  >    (setenv PATH "$layout/bin"
  >     (setenv OCAMLPATH "$layout/lib"
  >      (setenv CAML_LD_LIBRARY_PATH "$layout/lib/stublibs"
  >       (setenv OCAMLTOP_INCLUDE_PATH "$layout/lib/toplevel"
  >        (setenv MANPATH "$layout/man"
  >         (setenv OCAMLFIND_IGNORE_DUPS_IN "$layout/lib"
  >          (run ./probe.exe))))))))))
  > EOF
  $ dune build override --sandbox copy
  $ cat _build/default/override
  PATH: sandbox, isolated
  OCAMLPATH: sandbox, isolated
  CAML_LD_LIBRARY_PATH: sandbox, isolated
  OCAMLTOP_INCLUDE_PATH: sandbox, isolated
  MANPATH: sandbox, isolated
  OCAMLFIND_IGNORE_DUPS_IN: sandbox, isolated
